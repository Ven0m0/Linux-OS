#!/usr/bin/env bash
# Optimized: 2025-11-30 - Add support for soar and zoi; review phase triggers; clean env vars
# Standalone system update script for Arch-based systems.
set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
# Colors (trans palette)
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Helper functions
has() { command -v "$1" &> /dev/null; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "${BLU}${BLD}[*]${DEF} $*"; }
msg() { xecho "${GRN}${BLD}[+]${DEF} $*"; }
warn() { xecho "${YLW}${BLD}[!]${DEF} $*" >&2; }
err() { xecho "${RED}${BLD}[-]${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}
dbg() { [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :; }
cleanup_pacman_lock() { sudo rm -f /var/lib/pacman/db.lck &> /dev/null || :; }
main() {
  trap cleanup_pacman_lock EXIT INT TERM
  #============ Update Functions ============
  update_system() {
    log "🔄${BLU} System Packages${DEF}"
    sudo rm -f /var/lib/pacman/db.lck &> /dev/null || :
    if has paru; then
      paru -Syu --noconfirm --needed --skipreview
    else
      sudo pacman -Syu --noconfirm --needed
    fi
  }
  update_extras() {
    log "🔄${BLU} Extra Tooling${DEF}"
    if has topgrade; then
      local user_flags=('--disable=system' '--disable=self-update' '--disable=brew')
      topgrade -yc --no-retry "${user_flags[@]}" || :
    fi
    if has flatpak; then
      sudo flatpak update -y --noninteractive --appstream || :
      flatpak update -y --noninteractive -u || :
    fi
    if has rustup; then
      rustup update || :
      if has cargo-install-update; then
        cargo install-update -ag || :
      fi
    fi
    if has mise; then
      mise p i -ay
      mise prune -y
      mise up -y || :
    fi
    # Node toolchain (bun > pnpm > npm)
    if has bun; then
      bun update -g --latest || bun update -g
    elif has pnpm; then
      pnpm up -Lg || :
    elif has npm; then
      npm update -g || :
    fi
    has micro && micro -plugin update || :
    has fish && fish -c "fish_update_completions; and fisher update" || :
    # Soar: system-wide update assistant, if available (https://github.com/tlancer-x/soar)
    has soar && sudo soar upgrade --all --noconfirm || :
    # Zoi: Zellij plugin manager, if available (https://github.com/zellij-org/zoi)
    has zoi && zoi upgrade --yes --all || :
  }

  update_python() {
    has uv || return 0
    log "🔄${BLU} Python Environment (uv)${DEF}"
    mapfile -t pkgs < <(uv tool list --format=json 2> /dev/null | jq -r '.[].name')
    if [[ ${#pkgs[@]} -gt 0 ]]; then
      uv tool upgrade "${pkgs[@]}" || :
    fi
    mapfile -t outdated < <(uv pip list --outdated --format=json 2> /dev/null | jq -r '.[].name')
    if [[ ${#outdated[@]} -gt 0 ]]; then
      uv pip install -Uq --system --no-break-system-packages "${outdated[@]}" || :
    fi
  }
  update_maintenance() {
    log "🔄${BLU} System Maintenance${DEF}"
    local cmd
    for cmd in fc-cache-reload update-desktop-database update-ca-trust update-pciids update-smart-drivedb fwupdmgr; do
      has "$cmd" && sudo "$cmd" || :
    done
    printf 'Syncing time...\n'
    sudo systemctl restart systemd-timesyncd || :
    if has bootctl && [[ -d /sys/firmware/efi ]]; then
      sudo bootctl update || :
    fi
    if has mkinitcpio; then
      sudo mkinitcpio -P || :
    elif has dracut; then
      sudo dracut --regenerate-all --force || :
    elif [[ -x /usr/lib/booster/regenerate_images ]]; then
      sudo /usr/lib/booster/regenerate_images || :
    fi
  }
  #============ Execution ============
  log "\n${GRN}Meow! System Update Starting (> ^ <)${DEF}"
  update_system
  update_extras
  update_python
  update_maintenance
  log "\n${GRN}All done ✅${DEF}"
}
main "$@"
