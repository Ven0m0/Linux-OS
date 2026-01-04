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
    echo "Removing stale lock..."
    sudo rm -f /var/lib/pacman/db.lck
  fi

  if [[ -n $aur_helper ]]; then
    $aur_helper -Syu --noconfirm
  else
    sudo pacman -Syu --noconfirm
  fi
}

up_apps() {
  if has flatpak; then
    log "Flatpak Update"
    flatpak update -y
    try flatpak uninstall --unused -y
  fi
  if has snap; then
    log "Snap Update"
    sudo snap refresh
  fi
  if has bauh; then
    log "Bauh Update"
    bauh-cli update --system --no-confirm
  fi
}

up_dev() {
  log "Dev Tools Update"
  # Rust
  if has rustup; then
    info "Rust"
    rustup update
    has cargo-install-update && cargo install-update -a
  fi

  # Python
  if has uv; then
    info "Python (uv)"
    uv tool upgrade --all
    # Update system packages via uv if managing a venv or system-site-packages
    try uv pip install -U $(uv pip list --outdated --format=freeze 2>/dev/null | awk -F== '{print $1}')
  fi

  # Node / JS
  if has npm; then
    info "Node (npm)"
    try npm update -g
  fi
  if has bun; then
    info "Bun"
    try bun upgrade
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

  if has dracut; then
    try sudo dracut --regenerate-all --force
  elif has mkinitcpio; then
    try sudo mkinitcpio -P
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
      -s|--sys) mode="sys" ;; -a|--apps) mode="apps" ;;
      -d|--dev) mode="dev" ;; -m|--maint) mode="maint" ;;
      -h|--help) usage ;; *) die "Unknown arg: $1" ;;
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
