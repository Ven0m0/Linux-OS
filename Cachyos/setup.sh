#!/usr/bin/env bash
# setup.sh - Optimized System Setup
set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'
export LC_ALL=C LANG=C

# --- Helpers ---
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
has() { command -v "$1" >/dev/null; }
try() { "$@" >/dev/null 2>&1 || true; }
log() { printf "%b[+]%b %s\n" "$G" "$X" "$*"; }
die() { printf "%b[!]%b %s\n" "$R" "$X" "$*" >&2; exit 1; }
add_repo() {
  grep -q "\[$1\]" /etc/pacman.conf || printf "\n[%s]\nServer = %s\n" "$1" "$2" | sudo tee -a /etc/pacman.conf >/dev/null
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
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
  fi

  # Frogminer & Valve (Optional - uncomment if needed)
  # add_repo "frogminer" "https://frogminer.dev/repo/\$arch"
  # add_repo "valve-aur" "https://repo.steampowered.com/arch/valve-aur"
  
  sudo pacman -Sy --noconfirm
  has paru || { sudo pacman -S --needed --noconfirm base-devel git; git clone https://aur.archlinux.org/paru-bin.git; cd paru-bin; makepkg -si --noconfirm; cd ..; rm -rf paru-bin; }
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
  [[ -f steam.txt ]] && mapfile -t -O "${#pkgs[@]}" pkgs < steam.txt
  
  paru -S --needed --noconfirm "${pkgs[@]}"
}

setup_configs() {
  log "Applying configurations..."
  
  # VS Code Settings
  if has code; then
    local vs_conf="$HOME/.config/Code/User/settings.json"
    mkdir -p "$(dirname "$vs_conf")"
    [[ ! -f $vs_conf ]] && echo "{}" > "$vs_conf"
    
    local -A settings=(
      ["telemetry.telemetryLevel"]="off"
      ["update.mode"]="none"
      ["git.autofetch"]="false"
      ["extensions.autoUpdate"]="false"
      ["workbench.startupEditor"]="none"
    )
    
    local tmp; tmp=$(mktemp)
    for k in "${!settings[@]}"; do
      jq --arg k "$k" --arg v "${settings[$k]}" '.[$k] = $v' "$vs_conf" > "$tmp" && mv "$tmp" "$vs_conf"
    done
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
  has rustup && { rustup default stable; rustup component add rust-analyzer; }
}

# --- Main ---
main() {
  [[ $EUID -eq 0 ]] && die "Run as user, not root."
  
  setup_repos
  install_pkgs
  setup_configs
  setup_rust
  
  log "Cleanup..."
  try sudo pacman -Rns $(pacman -Qdtq) --noconfirm
  try sudo fstrim -av
  
  log "Setup complete! Reboot recommended."
}

main "$@"
