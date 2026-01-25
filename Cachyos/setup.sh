#!/usr/bin/env bash
# setup.sh - Optimized System Setup
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
LC_ALL=C LANG=C PYTHONOPTIMIZE=1

# --- Colors ---
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# --- Helpers ---
has() { command -v "$1" &>/dev/null; }
try() { "$@" >/dev/null 2>&1 || true; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "${GRN}[+]${DEF} $*"; }
warn() { xecho "${YLW}[!]${DEF} $*"; }
err() { xecho "${RED}[!]${DEF} $*" >&2; }
die() { err "$*"; exit "${2:-1}"; }
dbg() { [[ ${DEBUG:-0} -eq 1 ]] && xecho "[DBG] $*" || :; }

# --- Cleanup & Error Handling ---
WORKDIR=$(mktemp -d)
cleanup() {
  set +e
  [[ -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}
on_err() { err "failed at line ${1:-?}"; }
trap 'cleanup' EXIT
trap 'on_err $LINENO' ERR
trap ':' INT TERM

# --- Tool Detection ---
pm_detect() {
  if has paru; then printf 'paru'; return; fi
  if has yay; then printf 'yay'; return; fi
  if has pacman; then printf 'pacman'; return; fi
  printf ''
}
PKG_MGR=${PKG_MGR:-$(pm_detect)}

add_repo() {
  grep -q "\[$1\]" /etc/pacman.conf || printf "\n[%s]\nServer = %s\n" "$1" "$2" | sudo tee -a /etc/pacman.conf &>/dev/null
}

# --- Core Logic ---
setup_repos() {
  log "Configuring repositories..."
  # Enable Multilib
  sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
  # Chaotic AUR
  if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n" | sudo tee -a /etc/pacman.conf >/dev/null
  fi
  sudo pacman -Sy --noconfirm
  has paru || {
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru-bin.git "$WORKDIR/paru-bin"
    (cd "$WORKDIR/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$WORKDIR/paru-bin"
  }
}

install_pkgs() {
  log "Installing packages..."
  local -a pkgs=(
    # --- System ---
    base-devel linux-zen linux-zen-headers linux-firmware intel-ucode
    btrfs-progs networkmanager bluez bluez-utils pipewire pipewire-pulse
    # --- Tools ---
    git fish zsh neovim starship bat eza fzf ripgrep fd zoxide
    unzip p7zip unrar wget curl htop btop fastfetch
    # --- Desktop ---
    plasma-meta konsole dolphin ark spectacle gwenview kcalc
    # --- Dev ---
    code rustup go nodejs npm python python-pip docker docker-compose
  )
  # Append packages from text files if they exist
  [[ -f steam.txt ]] && mapfile -t -O "${#pkgs[@]}" pkgs <steam.txt
  local pkg_file="$(dirname "$0")/packages.txt"
  if [[ -f "$pkg_file" ]]; then
    log "Including packages from $pkg_file"
    mapfile -t -O "${#pkgs[@]}" pkgs < "$pkg_file"
  fi
  paru -S --needed --noconfirm "${pkgs[@]}"
}

setup_configs() {
  log "Applying configurations..."
  # VS Code Settings
  if has code && has jq; then
    local vs_conf="$HOME/.config/Code/User/settings.json"
    mkdir -p "$(dirname "$vs_conf")"
    [[ ! -f $vs_conf ]] && printf '{}\n' >"$vs_conf"
    local -A settings=(
      ["telemetry.telemetryLevel"]="off"
      ["update.mode"]="none"
      ["git.autofetch"]="false"
      ["extensions.autoUpdate"]="false"
      ["workbench.startupEditor"]="none"
    )
    local tmp
    tmp=$(mktemp)
    for k in "${!settings[@]}"; do
      jq --arg k "$k" --arg v "${settings[$k]}" '.[$k] = $v' "$vs_conf" >"$tmp" && mv "$tmp" "$vs_conf"
    done
  elif has code; then
    warn "jq not found, skipping VS Code settings configuration"
  fi
  # Shells
  for shell in bash fish zsh; do
    [[ -d "Home/.config/$shell" ]] && cp -r "Home/.config/$shell" "$HOME/.config/"
  done
  # Services
  local svcs=(NetworkManager bluetooth sshd docker)
  for s in "${svcs[@]}"; do try sudo systemctl enable --now "$s"; done
}

setup_rust() {
  log "Setting up Rust..."
  export RUSTUP_HOME="$HOME/.rustup" CARGO_HOME="$HOME/.cargo"
  has rustup && {
    rustup default stable
    rustup component add rust-analyzer
  }
}

setup_flatpak(){
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --system io.github.flattool.Warehouse -y
}
setup_am(){
  am -i am-gui
  am -i nix-portable
  am -i auto-claude
}
export_pkgs() {
  log "Exporting packages to packages.txt..."
  # Get explicitly installed packages (native + foreign/AUR)
  pacman -Qqe > "$(dirname "$0")/packages.txt"
  log "Export complete: $(dirname "$0")/packages.txt"
}

# Special permissions for SSH keys (keep private)
if [ -d "$HOME/.ssh" ]; then
    log "Checking SSH key permissions..."
    find "$HOME/.ssh" -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
    find "$HOME/.ssh" -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
    log "SSH key permissions verified"
fi
# Special permissions for GPG keys (keep private)
if [ -d "$HOME/.gnupg" ]; then
    log "Checking GPG key permissions..."
    chmod 700 "$HOME/.gnupg" 2>/dev/null || true
    find "$HOME/.gnupg" -name "*.gpg" -exec chmod 600 {} \; 2>/dev/null || true
    log "GPG key permissions verified"
fi
# Fix scripts in .local/bin
find "$HOME/.local/bin" -type f ! -executable -exec chmod +x {} \;
echo "✓ Fixed .local/bin scripts"

# --- Main ---
main() {
  if [[ "${1:-}" == "--export" ]]; then
    export_pkgs
    exit 0
  fi
  [[ $EUID -eq 0 ]] && die "Run as user, not root."
  setup_repos
  # Check for packages.txt in the script's directory
  local pkg_file="$(dirname "$0")/packages.txt"
  if [[ -f "$pkg_file" ]]; then
    log "Found packages.txt, installing from export..."
    # If using packages.txt, we likely want to rely mostly on it, 
    # but we can pass it to the install function or modify the logic there.
    # For now, let's just make install_pkgs aware of it.
  fi
  install_pkgs
  setup_configs
  setup_rust
  log "Cleanup..."
  local -a orphans
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
  if (( ${#orphans[@]} > 0 )); then
    try sudo pacman -Rns --noconfirm "${orphans[@]}"
  fi
  try sudo fstrim -av
  log "Setup complete! Reboot recommended."
}

main "$@"
