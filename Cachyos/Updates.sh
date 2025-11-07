#!/usr/bin/env bash
# Standalone system update script for Arch-based systems.
#============ Configuration & Bootstrap ============
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
#============ Color & Formatting ============
BLU=$'\e[34m' GRN=$'\e[32m' YLW=$'\e[33m' RED=$'\e[31m' DEF=$'\e[0m'
#============ Core Helpers ============
xecho(){ printf '%b\n' "$*"; }
has(){ command -v "$1" &>/dev/null; }

main(){
  local PRIV_CMD
  get_priv_cmd(){
    local cmd
    for cmd in sudo-rs sudo doas; do has "$cmd" && printf '%s' "$cmd" && return; done
    [[ $EUID -eq 0 ]] || { xecho "${RED}No sudo tool found${DEF}"; exit 1; }
  }
  PRIV_CMD=$(get_priv_cmd)
  [[ -n $PRIV_CMD && $EUID -ne 0 ]] && "$PRIV_CMD" -v || :
  run_priv(){ if [[ $EUID -eq 0 || -z $PRIV_CMD ]]; then "$@"; else "$PRIV_CMD" -- "$@"; fi; }
  cleanup(){ run_priv rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
  trap cleanup EXIT INT TERM
  #============ Update Functions ============
  update_system(){
    local pkgmgr aur_opts=()
    xecho "🔄${BLU} System Packages${DEF}"
    if has paru; then pkgmgr=paru; aur_opts=(--batchinstall --fmflags --skipinteg --nokeepsrc);
    elif has yay; then pkgmgr=yay; aur_opts=(--answerclean y --answerdiff n);
    else pkgmgr=pacman; fi
    cleanup
    run_priv "$pkgmgr" -Sy --needed archlinux-keyring --noconfirm &>/dev/null || :
    [[ -f /var/lib/pacman/sync/core.files ]] || run_priv pacman -Fy --noconfirm &>/dev/null || :
    if [[ $pkgmgr == pacman ]]; then
      run_priv pacman -Syu --noconfirm
    else
      local args=(--noconfirm --needed --sudoloop --bottomup --skipreview --cleanafter --removemake "${aur_opts[@]}")
      "$pkgmgr" -Sua --devel "${args[@]}" &>/dev/null || :
      "$pkgmgr" -Syu "${args[@]}"
    fi
  }
  
  update_extras(){
    xecho "🔄${BLU} Extra Tooling${DEF}"
    if has topgrade; then
      local user_flags=('--disable=system' '--disable=self-update' '--disable=brew')
      topgrade -yc --no-retry "${user_flags[@]}" &>/dev/null || :
    fi
    if has flatpak; then
      run_priv flatpak update -y --noninteractive --appstream &>/dev/null || :
      flatpak update -y --noninteractive &>/dev/null || :
    fi
    if has rustup; then
      rustup update &>/dev/null || :
      if has cargo-update && has cargo-install-update; then
        cargo install-update -ag &>/dev/null || :
      fi
    fi
    has mise && { mise p i -ay &>/dev/null || :; mise up -y &>/dev/null || :; mise prune -y &>/dev/null || :; }
    has bun && { bun i -g --only-missing &>/dev/null || :; bun update -g --latest &>/dev/null || :; }
    has pnpm && pnpm up -Lg &>/dev/null || :
    has micro && micro -plugin update &>/dev/null || :
    has fish && fish -c "fish_update_completions; and command -v fisher &>/dev/null and fisher update" &>/dev/null || :
  }
  
  update_python(){
    if ! has uv; then return 0; fi
    xecho "🔄${BLU} Python Environment (uv)${DEF}"
    uv self update &>/dev/null || :
    mapfile -t pkgs < <(uv tool list --format=json | jq -r '.[].name' 2>/dev/null)
    [[ ${#pkgs[@]} -gt 0 ]] && uv tool upgrade "${pkgs[@]}" &>/dev/null || :
    mapfile -t outdated < <(uv pip list --outdated --format=json | jq -r '.[].name' 2>/dev/null)
    if [[ ${#outdated[@]} -gt 0 ]]; then
      uv pip install -Uq --system --no-break-system-packages "${outdated[@]}" &>/dev/null || :
    fi
  }
  
  update_maintenance(){
    xecho "🔄${BLU} System Maintenance${DEF}"
    local cmd
    for cmd in fc-cache-reload update-desktop-database update-pciids update-smart-drivedb fwupdmgr; do
      has "$cmd" && run_priv "$cmd" &>/dev/null || :
    done
    
    if has bootctl && [[ -d /sys/firmware/efi ]]; then
      run_priv bootctl update &>/dev/null || :
    fi
    
    if has mkinitcpio; then
      run_priv mkinitcpio -P &>/dev/null || :
    elif has dracut; then
      run_priv dracut --regenerate-all --force &>/dev/null || :
    elif [[ -x /usr/lib/booster/regenerate_images ]]; then
      run_priv /usr/lib/booster/regenerate_images &>/dev/null || :
    fi
  }
  
  #============ Execution ============
  xecho "\n${GRN} Meow! System Update Starting (> ^ <)${DEF}"
  update_system
  update_extras
  update_python
  update_maintenance
  xecho "\n${GRN}All done ✅${DEF}\n"
}

main "$@"
