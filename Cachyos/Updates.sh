#!/usr/bin/env bash
# System update script for Arch-based systems
# Updates system packages, AUR packages, and various tooling

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/base.sh" || exit 1
source "${SCRIPT_DIR}/../lib/arch.sh" || exit 1
source "${SCRIPT_DIR}/../lib/ui.sh" || exit 1

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
  cleanup_pacman_lock
}

# ============================================================================
# Update Functions
# ============================================================================

update_system() {
  local pkgmgr
  local -a aur_opts

  info "System Packages"

  # Use cached package manager detection
  pkgmgr=$(get_pkg_manager)
  mapfile -t aur_opts < <(get_aur_opts)

  # Clean lock file before updating
  cleanup_pacman_lock

  # Update keyring first
  run_priv "$pkgmgr" -Sy --needed archlinux-keyring --noconfirm &>/dev/null || :

  # Update file database if missing
  [[ -f /var/lib/pacman/sync/core.files ]] || \
    run_priv pacman -Fy --noconfirm &>/dev/null || :

  # Perform system update
  if [[ $pkgmgr == pacman ]]; then
    run_priv pacman -Syu --noconfirm
  else
    local -a args=(
      --noconfirm --needed --sudoloop --bottomup
      --skipreview --cleanafter --removemake
      "${aur_opts[@]}"
    )
    "$pkgmgr" -Sua --devel "${args[@]}" &>/dev/null || :
    "$pkgmgr" -Syu "${args[@]}"
  fi

  ok "System packages updated"
}

update_extras() {
  info "Extra Tooling"

  # Topgrade
  if has topgrade; then
    local -a user_flags=(
      '--disable=system'
      '--disable=self-update'
      '--disable=brew'
    )
    topgrade -yc --no-retry "${user_flags[@]}" &>/dev/null || :
  fi

  # Flatpak
  if has flatpak; then
    run_priv flatpak update -y --noninteractive --appstream &>/dev/null || :
    flatpak update -y --noninteractive &>/dev/null || :
  fi

  # Rust toolchain
  if has rustup; then
    rustup update &>/dev/null || :
    if has cargo-update && has cargo-install-update; then
      cargo install-update -ag &>/dev/null || :
    fi
  fi

  # mise (polyglot tool version manager)
  if has mise; then
    mise p i -ay &>/dev/null || :
    mise up -y &>/dev/null || :
    mise prune -y &>/dev/null || :
  fi

  # Bun
  if has bun; then
    bun i -g --only-missing &>/dev/null || :
    bun update -g --latest &>/dev/null || :
  fi

  # pnpm
  has pnpm && pnpm up -Lg &>/dev/null || :

  # Micro editor
  has micro && micro -plugin update &>/dev/null || :

  # Fish shell
  has fish && \
    fish -c "fish_update_completions; and command -v fisher &>/dev/null and fisher update" &>/dev/null || :

  ok "Extra tooling updated"
}

update_python() {
  if ! has uv; then
    return 0
  fi

  info "Python Environment (uv)"

  # Update uv itself
  uv self update &>/dev/null || :

  # Update uv tools
  local -a pkgs
  mapfile -t pkgs < <(uv tool list --format=json | jq -r '.[].name' 2>/dev/null)
  [[ ${#pkgs[@]} -gt 0 ]] && uv tool upgrade "${pkgs[@]}" &>/dev/null || :

  # Update outdated pip packages
  local -a outdated
  mapfile -t outdated < <(uv pip list --outdated --format=json | jq -r '.[].name' 2>/dev/null)
  if [[ ${#outdated[@]} -gt 0 ]]; then
    uv pip install -Uq --system --no-break-system-packages "${outdated[@]}" &>/dev/null || :
  fi

  ok "Python environment updated"
}

update_maintenance() {
  info "System Maintenance"

  # Update various system databases
  local -a maint_cmds=(
    fc-cache-reload
    update-desktop-database
    update-pciids
    update-smart-drivedb
    fwupdmgr
  )

  local cmd
  for cmd in "${maint_cmds[@]}"; do
    has "$cmd" && run_priv "$cmd" &>/dev/null || :
  done

  # Update bootloader (EFI systems)
  if has bootctl && [[ -d /sys/firmware/efi ]]; then
    run_priv bootctl update &>/dev/null || :
  fi

  # Regenerate initramfs
  if has mkinitcpio; then
    run_priv mkinitcpio -P &>/dev/null || :
  elif has dracut; then
    run_priv dracut --regenerate-all --force &>/dev/null || :
  elif [[ -x /usr/lib/booster/regenerate_images ]]; then
    run_priv /usr/lib/booster/regenerate_images &>/dev/null || :
  fi

  ok "System maintenance completed"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
  # Initialize privilege tool
  PRIV_CMD=$(init_priv)

  # Setup cleanup trap
  trap cleanup EXIT INT TERM

  # Print banner
  print_named_banner "update" "Meow! System Update Starting (> ^ <)"

  # Run updates
  update_system
  update_extras
  update_python
  update_maintenance

  # Done!
  printf '\n'
  ok "All done! ✅"
  printf '\n'
}

main "$@"
