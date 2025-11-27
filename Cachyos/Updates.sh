#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques
# Standalone system update script for Arch-based systems.

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Color definitions
GRN=$'\e[32m'
BLU=$'\e[34m'
DEF=$'\e[0m'

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# Check if command exists
has(){ command -v "$1" &>/dev/null; }

# Logging function
log(){ printf '%b\n' "$*"; }

# Package manager detection with caching
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

get_pkg_manager(){
  if [[ -z $_PKG_MGR_CACHED ]]; then
    local pkgmgr
    if has paru; then
      pkgmgr=paru
      _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc)
    elif has yay; then
      pkgmgr=yay
      _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
    else
      pkgmgr=pacman
      _AUR_OPTS_CACHED=()
    fi
    _PKG_MGR_CACHED=$pkgmgr
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

get_aur_opts(){
  [[ -z $_PKG_MGR_CACHED ]] && get_pkg_manager >/dev/null
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

main(){
  cleanup(){ sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
  trap cleanup EXIT INT TERM
  #============ Update Functions ============
  update_system(){
    local pkgmgr aur_opts
    log "🔄${BLU} System Packages${DEF}"
    # Use cached package manager detection
    pkgmgr=$(get_pkg_manager)
    mapfile -t aur_opts < <(get_aur_opts)
    cleanup
    sudo "$pkgmgr" -Sy --needed archlinux-keyring --noconfirm &>/dev/null || :
    [[ -f /var/lib/pacman/sync/core.files ]] || sudo pacman -Fy --noconfirm &>/dev/null || :
    if [[ $pkgmgr == pacman ]]; then
      sudo pacman -Syu --noconfirm
    else
      local args=(--noconfirm --needed --sudoloop --bottomup --skipreview --cleanafter --removemake "${aur_opts[@]}")
      "$pkgmgr" -Sua --devel "${args[@]}" &>/dev/null || :
      "$pkgmgr" -Syu "${args[@]}"
    fi
  }

  update_extras(){
    log "🔄${BLU} Extra Tooling${DEF}"
    if has topgrade; then
      local user_flags=('--disable=system' '--disable=self-update' '--disable=brew')
      topgrade -yc --no-retry "${user_flags[@]}" &>/dev/null || :
    fi
    if has flatpak; then
      sudo flatpak update -y --noninteractive --appstream &>/dev/null || :
      flatpak update -y --noninteractive &>/dev/null || :
    fi
    if has rustup; then
      rustup update &>/dev/null || :
      cargo install-update -V &>/dev/null && cargo install-update -ag &>/dev/null
    fi
    has mise && {
      mise p i -ay &>/dev/null || :
      mise up -y &>/dev/null || :
      mise prune -y &>/dev/null || :
    }
    if has bun; then 
      bun update -g --latest &>/dev/null || :
    elif has pnpm; then
      pnpm up -Lg &>/dev/null || :
    elif has npm; then
      npm update -g &>/dev/null || :
    fi
    has micro && micro -plugin update &>/dev/null || :
    has fish && fish -c "fish_update_completions; and command -v fisher &>/dev/null and fisher update" &>/dev/null || :
  }

  update_python(){
    has uv || return 0
    log "🔄${BLU} Python Environment (uv)${DEF}"
    uv self update &>/dev/null || :
    mapfile -t pkgs < <(uv tool list --format=json | jq -r '.[].name' 2>/dev/null)
    [[ ${#pkgs[@]} -gt 0 ]] && uv tool upgrade "${pkgs[@]}" &>/dev/null || :
    mapfile -t outdated < <(uv pip list --outdated --format=json | jq -r '.[].name' 2>/dev/null)
    if [[ ${#outdated[@]} -gt 0 ]]; then
      uv pip install -Uq --system --no-break-system-packages "${outdated[@]}" &>/dev/null || :
    fi
  }

  update_maintenance(){
    log "🔄${BLU} System Maintenance${DEF}"
    local cmd
    for cmd in fc-cache-reload update-desktop-database update-ca-trust update-pciids update-smart-drivedb fwupdmgr; do
      has "$cmd" && sudo "$cmd" &>/dev/null || :
    done
    echo "Updating time..."
    sudo systemctl restart systemd-timesyncd
    if has bootctl && [[ -d /sys/firmware/efi ]]; then
      sudo bootctl update &>/dev/null || :
    fi
    if has mkinitcpio; then
      sudo mkinitcpio -P &>/dev/null || :
    elif has dracut; then
      sudo dracut --regenerate-all --force &>/dev/null || :
    elif [[ -x /usr/lib/booster/regenerate_images ]]; then
      sudo /usr/lib/booster/regenerate_images &>/dev/null || :
    fi
  }

  #============ Execution ============
  log "\n${GRN} Meow! System Update Starting (> ^ <)${DEF}"
  update_system
  update_extras
  update_python
  update_maintenance
  log "\n${GRN}All done ✅${DEF}\n"
}

main "$@"
