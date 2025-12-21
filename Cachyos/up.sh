#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# DESCRIPTION: Comprehensive system update orchestrator for Arch/CachyOS
#              Updates: pacman/AUR, flatpak, rust, python (uv), npm/bun/pnpm,
#              mise, topgrade, VSCode, fish, and system maintenance
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m' LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m' DEF=$'\e[0m' BLD=$'\e[1m'
has() { command -v "$1" &>/dev/null; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "${BLU}${BLD}[*]${DEF} $*"; }
msg() { xecho "${GRN}${BLD}[+]${DEF} $*"; }
warn() { xecho "${YLW}${BLD}[!]${DEF} $*" >&2; }
err() { xecho "${RED}${BLD}[-]${DEF} $*" >&2; }
dbg() { [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :; }
cleanup_pacman_lock() { sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
usage() {
  cat <<'EOF'
up.sh - Comprehensive Arch/CachyOS system update orchestrator

Usage: up.sh [OPTIONS]

Options:
  -h, --help     Show this help message
  --version      Show version

Updates:
  • System packages (pacman/paru/yay)
  • Flatpak apps (system + user)
  • Rust toolchain (rustup + cargo packages)
  • Python packages (uv tools + pip)
  • Node packages (bun/pnpm/npm global)
  • Mise/rtx managed tools
  • Topgrade integration
  • VSCode extensions
  • Fish completions + fisher
  • soar, am, zoi, gh extensions
  • System maintenance (bootctl, mkinitcpio, firmware)

Environment:
  DEBUG=1        Enable debug output

Examples:
  up.sh          # Full system update
  DEBUG=1 up.sh  # Debug mode
EOF
}
main() {
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
    --version)
      printf 'up.sh 1.0.0\n'
      exit 0
      ;;
  esac
  trap cleanup_pacman_lock EXIT INT TERM
  update_system() {
    log "🔄${BLU} System Packages${DEF}"
    sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :
    has paru && paru -Syuq --noconfirm --needed --skipreview || sudo pacman -Syuq --noconfirm --needed
  }
  update_extras() {
    log "🔄${BLU} Extra Tooling${DEF}"
    if has topgrade; then
      local user_flags=('--disable=system' '--disable=self-update' '--disable=brew')
      topgrade -yc --no-retry "${user_flags[@]}" || :
    fi
    has flatpak && {
      sudo flatpak update -y --noninteractive --appstream || :
      flatpak update -y --noninteractive -u || :
    }
    if has rustup; then
      rustup update || :
      has cargo-install-update && cargo install-update -ag || :
    fi
    if has mise; then
      mise p i -ay
      mise prune -y
      mise up -y || :
    fi
    if has bun; then
      bun update -g --latest || bun update -g
    elif has pnpm; then
      pnpm up -Lg || :
    elif has npm; then npm update -g || :; fi
    has micro && micro -plugin update || :
    if has ya && has yazi; then
      ya pkg upgrade
    fi
    has code && code --update-extensions || :
    has fish && fish -c "fish_update_completions; and fisher update" || :
    if has soar; then
      soar S -q
      soar u -q
      soar clean -q
    fi
    if has am; then
      am -s
      am -u
      am --icons --all
      am -c
    fi
    has zoi && zoi upgrade --yes --all || :
    has gh && gh extension upgrade --all || :
    has yt-dlp && yt-dlp --rm-cache-dir -U || :
  }
  update_python() {
    has uv || return 0
    log "🔄${BLU} Python Environment (uv)${DEF}"
    mapfile -t pkgs < <(uv tool list --format=json 2>/dev/null | jq -r '.[].name')
    [[ ${#pkgs[@]} -gt 0 ]] && uv tool upgrade "${pkgs[@]}" || :
    mapfile -t outdated < <(uv pip list --outdated --format=json 2>/dev/null | jq -r '.[].name')
    [[ ${#outdated[@]} -gt 0 ]] && uv pip install -Uq --system --no-break-system-packages "${outdated[@]}" || :
  }
  update_maintenance() {
    log "🔄${BLU} System Maintenance${DEF}"
    local cmd
    # Run independent maintenance commands in parallel
    for cmd in fc-cache-reload update-desktop-database update-ca-trust update-pciids update-smart-drivedb; do has "$cmd" && sudo "$cmd" & done
    has fwupdmgr && sudo fwupdmgr refresh &>/dev/null &
    wait
    printf 'Syncing time...\n'
    sudo systemctl restart systemd-timesyncd || :
    has bootctl && [[ -d /sys/firmware/efi ]] && sudo bootctl update || :
    if has mkinitcpio; then
      sudo mkinitcpio -P || :
    elif has dracut; then
      sudo dracut --regenerate-all --force || :
    elif [[ -x /usr/lib/booster/regenerate_images ]]; then sudo /usr/lib/booster/regenerate_images || :; fi
  }
  log "\n${GRN}Meow! System Update Starting (> ^ <)${DEF}"
  update_system
  update_extras
  update_python
  update_maintenance
  log "\n${GRN}All done ✅${DEF}"
}
main "$@"
