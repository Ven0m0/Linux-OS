#!/usr/bin/env bash
# setup.sh - CachyOS fresh install setup
set -Eeuo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C PYTHONOPTIMIZE=1

# When running via curl-pipe, set REPO_RAW to your raw content URL, e.g.:
# curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/setup.sh | REPO_RAW=https://raw.githubusercontent.com/USER/REPO/main bash
REPO_RAW="${REPO_RAW:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || echo "")"

# --- Colors ---
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'

# --- Helpers ---
has()  { command -v "$1" &>/dev/null; }
try()  { "$@" >/dev/null 2>&1 || true; }
log()  { printf '%b\n' "${GRN}[+]${DEF} $*"; }
warn() { printf '%b\n' "${YLW}[!]${DEF} $*"; }
err()  { printf '%b\n' "${RED}[!]${DEF} $*" >&2; }
die()  { err "$*"; exit "${2:-1}"; }

WORKDIR=$(mktemp -d)
cleanup() { set +e; rm -rf "${WORKDIR:-}"; }
trap 'cleanup' EXIT
trap 'err "failed at line $LINENO"' ERR
trap ':' INT TERM

# --- Package list loader ---
# Reads a pkg file: strips blank lines, comments (#), trims whitespace
read_pkgfile() {
  local content="$1"
  while IFS= read -r line; do
    line="${line%%#*}"       # strip inline comments
    line="${line//[[:space:]]/}"
    [[ -n $line ]] && printf '%s\n' "$line"
  done <<< "$content"
}

fetch_pkgfile() {
  local name="$1"  # e.g. "pacman" -> pkg/pacman.txt
  local path="pkg/${name}.txt"

  if [[ -n $SCRIPT_DIR && -f "$SCRIPT_DIR/$path" ]]; then
    cat "$SCRIPT_DIR/$path"
  elif [[ -n $REPO_RAW ]]; then
    curl -fsSL "${REPO_RAW%/}/$path"
  else
    warn "pkg/${name}.txt not found and REPO_RAW not set, skipping"
    return 0
  fi
}

load_pkgs() {
  local name="$1"
  local content
  content="$(fetch_pkgfile "$name")" || return 0
  read_pkgfile "$content"
}

# --- Repo & AUR helper setup ---
pm_detect() {
  for pm in paru yay pacman; do
    has "$pm" && printf '%s' "$pm" && return
  done
}
PKG_MGR="${PKG_MGR:-$(pm_detect)}"

setup_repos() {
  log "Configuring repositories..."

  sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

  if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' \
      | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  sudo pacman -Sy --noconfirm

  has paru || {
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru-bin.git "$WORKDIR/paru-bin"
    (cd "$WORKDIR/paru-bin" && makepkg -si --noconfirm)
  }
  PKG_MGR=paru
}

install_pkgs() {
  log "Installing pacman packages..."
  local -a pacman_pkgs
  mapfile -t pacman_pkgs < <(load_pkgs pacman)
  if (( ${#pacman_pkgs[@]} > 0 )); then
    paru -S --needed --noconfirm "${pacman_pkgs[@]}" || warn "Some pacman packages failed"
  fi

  log "Installing AUR packages..."
  local -a aur_pkgs
  mapfile -t aur_pkgs < <(load_pkgs aur)
  if (( ${#aur_pkgs[@]} > 0 )); then
    paru -S --needed --noconfirm "${aur_pkgs[@]}" || warn "Some AUR packages failed"
  fi
}

install_bun_pkgs() {
  has bun || { warn "bun not found, skipping bun packages"; return 0; }
  log "Installing bun packages..."
  local -a bun_pkgs
  mapfile -t bun_pkgs < <(load_pkgs bun)
  (( ${#bun_pkgs[@]} > 0 )) && bun install -g "${bun_pkgs[@]}" || warn "Some bun packages failed"
}

install_uv_pkgs() {
  has uv || { warn "uv not found, skipping uv packages"; return 0; }
  log "Installing uv/pip packages..."
  local -a uv_pkgs
  mapfile -t uv_pkgs < <(load_pkgs uv)
  (( ${#uv_pkgs[@]} > 0 )) && uv tool install "${uv_pkgs[@]}" || warn "Some uv packages failed"
}

setup_rust() {
  has rustup || { warn "rustup not found, skipping"; return 0; }
  log "Setting up Rust..."
  rustup default stable
  rustup target add wasm32-unknown-unknown
  rustup component add rust-std-wasm32-unknown-unknown llvm-bitcode-linker llvm-tools rust-analyzer rust-src
}

setup_flatpak() {
  has flatpak || return 0
  log "Setting up Flatpak..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --system -y io.github.flattool.Warehouse || true
}

setup_services() {
  log "Enabling services..."
  local svcs=(NetworkManager bluetooth sshd)
  for s in "${svcs[@]}"; do try sudo systemctl enable --now "$s"; done
}

fix_permissions() {
  log "Fixing permissions..."
  if [[ -d $HOME/.ssh ]]; then
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -name "id_*" ! -name "*.pub" -exec chmod 600 {} +
    find "$HOME/.ssh" -name "*.pub"                 -exec chmod 644 {} +
  fi
  if [[ -d $HOME/.gnupg ]]; then
    chmod 700 "$HOME/.gnupg"
    find "$HOME/.gnupg" -name "*.gpg" -exec chmod 600 {} +
  fi
  if [[ -d $HOME/.local/bin ]]; then
    find "$HOME/.local/bin" -type f ! -executable -exec chmod +x {} +
  fi
}

export_pkgs() {
  log "Exporting installed packages..."
  local out="${SCRIPT_DIR:-.}/packages.txt"
  pacman -Qqe > "$out"
  log "Exported to $out"
}

cleanup_orphans() {
  local -a orphans
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
  if (( ${#orphans[@]} > 0 )); then
    log "Removing ${#orphans[@]} orphans..."
    try sudo pacman -Rns --noconfirm "${orphans[@]}"
  fi
}

# --- Main ---
main() {
  case "${1:-}" in
    --export) export_pkgs; return 0 ;;
    --help)
      printf 'Usage: %s [--export]\n' "${BASH_SOURCE[0]}"
      printf '  REPO_RAW=URL  fetch pkg/*.txt from remote (for curl-pipe mode)\n'
      return 0 ;;
  esac

  [[ $EUID -eq 0 ]] && die "Run as user, not root."

  setup_repos
  install_pkgs
  install_bun_pkgs
  install_uv_pkgs
  setup_rust
  setup_flatpak
  setup_services
  fix_permissions
  cleanup_orphans

  try sudo fstrim -av
  log "Setup complete! Reboot recommended."
}

main "$@"
