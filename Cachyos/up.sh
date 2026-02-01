#!/usr/bin/env bash
# up.sh - Optimized System Update Orchestrator
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# --- Config & Helpers ---
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
has() { command -v "$1" &>/dev/null; }
try() { "$@" >/dev/null 2>&1 || true; }
log() { printf "%b[+]%b %s\n" "$G" "$X" "$*"; }
info() { printf "%b[*]%b %s\n" "$B" "$X" "$*"; }
warn() { printf "%b[!]%b %s\n" "$Y" "$X" "$*" >&2; }
die() {
  printf "%b[!]%b %s\n" "$R" "$X" "$*" >&2
  exit 1
}

# --- Update Functions ---
up_sys() {
  log "System Update (Arch)"
  local aur_helper=""
  if has paru; then
    aur_helper="paru"
  elif has yay; then
    aur_helper="yay"
  else log "No AUR helper found, using pacman"; fi

  # Unlock database if stale lock exists
  if [[ -f /var/lib/pacman/db.lck ]]; then
    warn "Removing stale pacman lock..."
    sudo rm -f /var/lib/pacman/db.lck
  fi

  if [[ -n $aur_helper ]]; then
    $aur_helper -Syu --noconfirm
  else
    sudo pacman -Syu --noconfirm
  fi

  if has topgrade; then
    log "Running topgrade..."
    topgrade -y --cleanup --allow-root --disable-predefined-git-repos --no-retry --no-self-update --skip-notify --disable yadm --disable rustup --disable config_update --disable system
  fi
}

up_apps() {
  if has flatpak; then
    log "Flatpak Update"
    flatpak update -y --noninteractive --appstream
    sudo flatpak update -y --noninteractive --appstream
    flatpak update -yu --noninteractive --force-remove
    sudo flatpak update -y --noninteractive --force-remove
    try flatpak uninstall --unused -y --noninteractive --force-remove
  fi
}

up_dev() {
  log "Dev Tools Update"
  # Rust
  if has rustup; then
    info "Rust"
    rustup update
    has cargo-install-update && cargo install-update -ag
  fi
  # Python
  if has uv; then
    info "Python (uv)"
    uv tool upgrade --all
    # Update system packages via uv if managing a venv or system-site-packages
    # Only if there are outdated packages
    local outdated
    outdated=$(uv pip list --outdated --format=freeze 2>/dev/null | awk -F== '{print $1}')
    if [[ -n $outdated ]]; then
      try uv pip install -U $outdated
    fi
  fi
  # Node / JS
  if has bun; then
    info "Bun"
    try bun update -g -r --latest --trust --linker=hoisted
  elif has npm; then
    try npm update -g --install-strategy hoisted
  fi
  # Go
  has go && {
    info "Go"
    go clean -modcache
  }
}

up_maint() {
  log "System Maintenance"
  # Refresh caches & DBs
  try sudo fc-cache -f
  try sudo update-desktop-database
  has update-pciids && try sudo update-pciids
  has update-ccache-links && sudo update-ccache-links

  # Firmware
  if has fwupdmgr; then
    info "Firmware"
    try sudo fwupdmgr refresh
    try sudo fwupdmgr update -y
  fi

  # Time Sync
  try sudo systemctl restart systemd-timesyncd

  # Bootloader / InitRAMFS
  info "Bootloader/InitRAMFS"
  if has sdboot-manage; then
    sudo sdboot-manage update
  elif has bootctl && [[ -d /sys/firmware/efi ]]; then
    sudo bootctl update
  fi

  if has limine-mkinitcpio; then
    sudo limine-mkinitcpio
  elif has mkinitcpio; then
    try sudo mkinitcpio -P
  elif has /usr/lib/booster/regenerate_images; then
    sudo /usr/lib/booster/regenerate_images
  elif has dracut-rebuild; then
    sudo dracut-rebuild
  fi
}

usage() {
  cat <<EOF
up.sh - System Updater
Usage: ${0##*/} [OPTIONS]
Options:
  -s, --sys     Update System (Pacman/AUR) only
  -a, --apps    Update Apps (Flatpak/Snap) only
  -d, --dev     Update Dev tools (Rust/Py/Node) only
  -m, --maint   Run Maintenance only
  -h, --help    Show help
No args runs ALL updates.
EOF
  exit 0
}

# --- Main ---
main() {
  local mode="all"
  while [[ $# -gt 0 ]]; do
    case $1 in
      -s | --sys) mode="sys" ;; -a | --apps) mode="apps" ;;
      -d | --dev) mode="dev" ;; -m | --maint) mode="maint" ;;
      -h | --help) usage ;; *) die "Unknown arg: $1" ;;
    esac
    shift
  done

  # Sudo refresh upfront
  sudo -v

  case $mode in
    sys) up_sys ;;
    apps) up_apps ;;
    dev) up_dev ;;
    maint) up_maint ;;
    all)
      up_sys
      up_apps
      up_dev
      up_maint
      ;;
  esac

  log "Update Complete!"
  if [[ -f /var/run/reboot-required ]]; then
    printf "%b[!] Reboot Required%b\n" "$Y" "$X"
  fi
}

main "$@"
