#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1

# Initialize privilege escalation
PRIV_CMD=$(init_priv)
export PRIV_CMD

# Setup cleanup trap
setup_cleanup_trap

# Setup build environment
setup_build_env

update_system(){
  local pkgmgr aur_opts=()
  xecho "🔄${BLU}System update${DEF}"
  if has paru; then
    pkgmgr=paru
    aur_opts=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    pkgmgr=yay
    aur_opts=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  else
    pkgmgr=pacman
  fi
  cleanup_pacman_lock
  run_priv "$pkgmgr" -Sy archlinux-keyring --noconfirm -q >/dev/null 2>&1 || :
  [[ -f /var/lib/pacman/sync/core.files ]] || run_priv pacman -Fy --noconfirm || :
  run_priv pacman -Fy --noconfirm >/dev/null 2>&1 || :
  if [[ $pkgmgr == paru ]]; then
    local args=(--noconfirm --needed --mflags '--skipinteg --skippgpcheck' --bottomup --skipreview --cleanafter --removemake --sudoloop --sudo "$PRIV_CMD" "${aur_opts[@]}")
    xecho "🔄${BLU}Updating AUR packages with ${pkgmgr}...${DEF}"
    "$pkgmgr" -Suyy "${args[@]}" >/dev/null 2>&1 || :
    "$pkgmgr" -Sua --devel "${args[@]}" >/dev/null 2>&1 || :
  else
    xecho "🔄${BLU}Updating system with pacman...${DEF}"
    run_priv pacman -Suyy --noconfirm --needed >/dev/null 2>&1 || :
  fi
}

update_extras(){
  if has topgrade; then
    xecho "🔄${BLU}Running Topgrade updates...${DEF}"
    local disable_user=(--disable={config_update,system,tldr,maza,yazi,micro})
    local disable_root=(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})
    LC_ALL=C topgrade -cy --skip-notify --no-self-update --no-retry "${disable_user[@]}" >/dev/null 2>&1 || :
    LC_ALL=C run_priv topgrade -cy --skip-notify --no-self-update --no-retry "${disable_root[@]}" >/dev/null 2>&1 || :
  fi

  if has flatpak; then
    xecho "🔄${BLU}Updating Flatpak...${DEF}"
    run_priv flatpak update -y --noninteractive --appstream
    flatpak update -yu --noninteractive
    run_priv flatpak update -y --noninteractive --force-remove >/dev/null 2>&1 || :
  fi

  if has rustup; then
    xecho "🔄${BLU}Updating Rust...${DEF}"
    HOME="$/home/${SUDO_USER:-$USER}"
    rustup update
    sudo -u $USER rustup update
    rustup self upgrade-data
    if has cargo; then
      xecho "🔄${BLU}Updating Cargo packages...${DEF}"
      local cargo_cmd=(cargo)
      for cmd in gg mommy clicker; do
        if has "cargo-$cmd"; then
          cargo_cmd=(cargo "$cmd")
          break
        fi
      done
      if "${cargo_cmd[@]}" install-update -Vq 2>/dev/null; then
        "${cargo_cmd[@]}" install-update -agfq
      fi
      has cargo-syu && "${cargo_cmd[@]}" syu -g
    fi
  fi
  if has mise; then
    mise p i -ay
    mise up -y
    mise prune -y
  fi
  if has bun; then
    bun i --only-missing
    bun update --latest -gr --quiet --linker=hoisted --concurrent-scripts=8
  elif has pnpm; then
    pnpm up -Lg
  fi
  has micro && micro -plugin update >/dev/null 2>&1 || :
  has yazi && ya pkg upgrade >/dev/null 2>&1 || :
  has tldr && run_priv tldr -cuq || :
  if has fish; then
    xecho "🔄${BLU}Updating Fish...${DEF}"
    fish -c "fish_update_completions" || :
    if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
      fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update" || :
    elif [[ -r ${HOME}/.config/fish/functions/fisher.fish ]]; then
      fish -c ". \"$HOME/.config/fish/functions/fisher.fish\"; and fisher update" || :
    fi
  fi
  if [[ -d ${HOME}/.basher ]] && git -C "${HOME}/.basher" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "${HOME}/.basher" pull --rebase --autostash --prune origin HEAD >/dev/null; then
      xecho "✅${GRN}Updated Basher${DEF}"
    else
      xecho "⚠️${YLW}Basher pull failed${DEF}"
    fi
  fi
  has update-alternatives && run_priv update-alternatives sync
}

update_python(){
  if has uv; then
    xecho "🔄${BLU}Updating UV...${DEF}"
    uv self update -q >/dev/null 2>&1 || xecho "⚠️${YLW}Failed to update UV${DEF}"
    xecho "🔄${BLU}Updating UV tools...${DEF}"
    if uv tool list -q >/dev/null 2>&1; then
      uv tool upgrade --all -q || xecho "⚠️${YLW}Failed to update UV tools${DEF}"
    else
      xecho "✅${GRN}No UV tools installed${DEF}"
    fi
    xecho "🔄${BLU}Updating Python packages...${DEF}"
    if has jq; then
      pkgs=$(uv pip list --outdated --format json | jq -r '.[].name' 2>/dev/null || :)
      if [[ -n $pkgs ]]; then
        uv pip install -Uq --system --no-break-system-packages --compile-bytecode --refresh "$pkgs" \
          >/dev/null 2>&1 || xecho "⚠️${YLW}Failed to update packages${DEF}"
      else
        xecho "✅${GRN}All Python packages are up to date${DEF}"
      fi
    else
      xecho "⚠️${YLW}jq not found, using fallback method${DEF}"
      uv pip install --upgrade -r <(uv pip list --format freeze) >/dev/null 2>&1 || \
        xecho "⚠️${YLW}Failed to update packages${DEF}"
    fi
    xecho "🔄${BLU}Updating Python interpreters...${DEF}"
    uv python update-shell -q
    uv python upgrade -q || xecho "⚠️${YLW}Failed to update Python versions${DEF}"
  fi
}

update_system_utils(){
  xecho "🔄${BLU}Running miscellaneous updates...${DEF}"
  local cmds=("fc-cache -f" "update-desktop-database" "update-pciids" "update-smart-drivedb" "update-ccache-links")
  for cmd in "${cmds[@]}"; do
    local cmd_name=${cmd%% *}
    has "$cmd_name" && run_priv "$cmd"
  done
  has update-leap && LC_ALL=C update-leap >/dev/null 2>&1 || :
  if has fwupdmgr; then
    xecho "🔄${BLU}Updating firmware...${DEF}"
    run_priv fwupdmgr refresh -y || :
    run_priv fwupdtool update || :
  fi
}

update_boot(){
  xecho "🔍${BLU}Checking boot configuration...${DEF}"
  if [[ -d /sys/firmware/efi ]] && has bootctl && run_priv bootctl is-installed -q >/dev/null 2>&1; then
    xecho "✅${GRN}systemd-boot detected, updating${DEF}"
    run_priv bootctl update -q >/dev/null 2>&1
    run_priv bootctl cleanup -q >/dev/null 2>&1
  else
    xecho "❌${RED}systemd-boot not present, skipping${DEF}"
  fi
  if has sdboot-manage; then
    xecho "🔄${BLU}Updating sdboot-manage...${DEF}"
    run_priv sdboot-manage remove >/dev/null 2>&1 || :
    run_priv sdboot-manage update >/dev/null 2>&1 || :
  fi
  xecho "🔄${BLU}Updating initramfs...${DEF}"
  if has update-initramfs; then
    run_priv update-initramfs
  else
    local initramfs_cmd=""
    for cmd in limine-mkinitcpio mkinitcpio dracut-rebuild; do
      if has "$cmd"; then
        initramfs_cmd="$cmd"
        break
      fi
    done
    if [[ -z $initramfs_cmd && -x /usr/lib/booster/regenerate_images ]]; then
      run_priv /usr/lib/booster/regenerate_images || :
    elif [[ -n $initramfs_cmd ]]; then
      if [[ $initramfs_cmd == mkinitcpio ]]; then
        run_priv "$initramfs_cmd" -P || :
      else
        run_priv "$initramfs_cmd" || :
      fi
    else
      xecho "${RED}No initramfs generator found, please update manually${DEF}"
    fi
  fi
}

main(){
  print_named_banner "update" "Meow (> ^ <)"
  checkupdates -dc >/dev/null 2>&1 || :
  run_system_maintenance modprobed-db
  run_system_maintenance hwclock -w
  run_system_maintenance updatedb
  run_system_maintenance chwd -a
  run_system_maintenance mandb
  update_system
  update_extras
  update_python
  update_system_utils
  update_boot
  xecho "\n${GRN}All done ✅ (> ^ <) Meow${DEF}\n"
}

main "$@"
