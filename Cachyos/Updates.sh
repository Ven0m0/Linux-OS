#!/usr/bin/env bash
# Optimized: 2025-11-30 - Add support for soar and zoi; review phase triggers; clean env vars
# Standalone system update script for Arch-based systems.

set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"

# Colors (trans flag palette)
BLU=$'\e[34m' GRN=$'\e[32m' DEF=$'\e[0m'
export BLU GRN DEF

# Core helper functions
has() { command -v -- "$1" &> /dev/null; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "$*"; }

# Package manager detection (cached)
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

detect_pkg_manager() {
  if [[ -n $_PKG_MGR_CACHED ]]; then
    printf '%s\n' "$_PKG_MGR_CACHED"
    printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
    return 0
  fi
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
  printf '%s\n' "$pkgmgr"
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager > /dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager > /dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

cleanup_pacman_lock() {
  sudo rm -f /var/lib/pacman/db.lck &> /dev/null || :
}

main() {
  trap cleanup_pacman_lock EXIT INT TERM
  #============ Update Functions ============
  update_system() {
    local pkgmgr aur_opts
    log "🔄${BLU} System Packages${DEF}"
    pkgmgr=$(get_pkg_manager)
    mapfile -t aur_opts < <(get_aur_opts)
    cleanup_pacman_lock
    sudo "$pkgmgr" -Sy --needed archlinux-keyring --noconfirm || :
    [[ -f /var/lib/pacman/sync/core.files ]] || sudo pacman -Fy --noconfirm || :
    if [[ $pkgmgr == pacman ]]; then
      sudo pacman -Syu --noconfirm
    else
      local args=(--noconfirm --needed --sudoloop --bottomup --skipreview --cleanafter --removemake "${aur_opts[@]}")
      "$pkgmgr" -Sua --devel "${args[@]}" || :
      "$pkgmgr" -Syu "${args[@]}"
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
      flatpak update -y --noninteractive || :
    fi
    if has rustup; then
      rustup update || :
      if has cargo-install-update; then
        cargo install-update -ag || :
      fi
    fi
    if has mise; then
      mise p i -ay || :
      mise up -y || :
      mise prune -y || :
    fi
    # Node toolchain (bun > pnpm > npm)
    if has bun; then
      bun update -g --latest || :
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
    if ! has uv; then return 0; fi
    log "🔄${BLU} Python Environment (uv)${DEF}"
    uv self update || :
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
