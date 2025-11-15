#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1

#=========== Configuration ============
QUIET=0
VERBOSE=0
DRYRUN=0
ASSUME_YES=0
MODE=""

# Override log function to respect QUIET
log() { ((QUIET)) || xecho "$*"; }

# Initialize privilege tool (renamed from SUDO to PRIV_CMD for consistency)
PRIV_CMD=$(init_priv)
export PRIV_CMD
# Keep SUDO as alias for backward compatibility
SUDO="$PRIV_CMD"



#=========== Update Functions ===========
# Note: run_system_maintenance is now provided by common.sh

update_system_packages() {
  local pkgmgr aur_opts
  log "🔄${BLU}System update${DEF}"
  # Use cached package manager detection
  pkgmgr=$(get_pkg_manager)
  mapfile -t aur_opts < <(get_aur_opts)

  # Remove pacman lock if exists
  cleanup_pacman_lock

  # Update keyring and file databases
  run_priv "$pkgmgr" -Sy archlinux-keyring --noconfirm -q &>/dev/null || :

  # Update file database only if it doesn't exist
  [[ -f /var/lib/pacman/sync/core.files ]] || run_priv pacman -Fy --noconfirm &>/dev/null || :

  # Run system updates
  if [[ $pkgmgr == paru ]]; then
    local args=(--noconfirm --needed --mflags '--skipinteg --skippgpcheck'
      --bottomup --skipreview --cleanafter --removemake
      --sudoloop --sudo "$SUDO" "${aur_opts[@]}")
    log "🔄${BLU}Updating AUR packages with ${pkgmgr}...${DEF}"
    "$pkgmgr" -Suyy "${args[@]}" &>/dev/null || :
    "$pkgmgr" -Sua --devel "${args[@]}" &>/dev/null || :
  else
    log "🔄${BLU}Updating system with pacman...${DEF}"
    run_priv pacman -Suyy --noconfirm --needed &>/dev/null || :
  fi
}

update_with_topgrade() {
  if has topgrade; then
    log "🔄${BLU}Running Topgrade updates...${DEF}"
    local disable_user=(--disable={config_update,system,tldr,maza,yazi,micro})
    local disable_root=(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})
    LC_ALL=C topgrade -cy --skip-notify --no-self-update --no-retry "${disable_user[@]}" &>/dev/null || :
    LC_ALL=C run_priv topgrade -cy --skip-notify --no-self-update --no-retry "${disable_root[@]}" &>/dev/null || :
  fi
}

update_flatpak() {
  if has flatpak; then
    log "🔄${BLU}Updating Flatpak...${DEF}"
    run_priv flatpak update -y --noninteractive --appstream &>/dev/null || :
    run_priv flatpak update -y --noninteractive --system --force-remove &>/dev/null || :
  fi
}

update_rust() {
  if has rustup; then
    log "🔄${BLU}Updating Rust...${DEF}"
    rustup update
    run_priv rustup update
    rustup self upgrade-data

    if has cargo; then
      log "🔄${BLU}Updating Cargo packages...${DEF}"
      local cargo_cmd=(cargo)
      for cmd in gg mommy clicker; do
        if has "cargo-$cmd"; then
          cargo_cmd=(cargo "$cmd")
          break
        fi
      done

      # Update cargo packages
      if "${cargo_cmd[@]}" install-update -Vq 2>/dev/null; then
        "${cargo_cmd[@]}" install-update -agfq
      fi
      has cargo-syu && "${cargo_cmd[@]}" syu -g
    fi
  fi
}

update_editors() {
  # Update editor plugins
  has micro && micro -plugin update &>/dev/null || :
  has yazi && ya pkg upgrade &>/dev/null || :
}

update_shells() {
  if has fish; then
    log "🔄${BLU}Updating Fish...${DEF}"
    fish -c "fish_update_completions" || :
    if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
      fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update" || :
    elif [[ -r ${HOME}/.config/fish/functions/fisher.fish ]]; then
      fish -c ". \"$HOME/.config/fish/functions/fisher.fish\"; and fisher update" || :
    fi
  fi

  # Update basher if installed
  if [[ -d ${HOME}/.basher ]] && git -C "${HOME}/.basher" rev-parse --is-inside-work-tree &>/dev/null; then
    if git -C "${HOME}/.basher" pull --rebase --autostash --prune origin HEAD >/dev/null; then
      log "✅${GRN}Updated Basher${DEF}"
    else
      log "⚠️${YLW}Basher pull failed${DEF}"
    fi
  fi

  # Update tldr cache
  has tldr && run_priv tldr -cuq || :
}

update_python() {
  if has uv; then
    log "🔄${BLU}Updating UV...${DEF}"
    uv self update -q &>/dev/null || log "⚠️${YLW}Failed to update UV${DEF}"

    log "🔄${BLU}Updating UV tools...${DEF}"
    if uv tool list -q &>/dev/null; then
      uv tool upgrade --all -q || log "⚠️${YLW}Failed to update UV tools${DEF}"
    else
      log "✅${GRN}No UV tools installed${DEF}"
    fi

    log "🔄${BLU}Updating Python packages...${DEF}"
    if has jq; then
      local pkgs
      # Optimize by only calling uv pip list once and parsing efficiently
      mapfile -t pkgs < <(uv pip list --outdated --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null || :)
      if [[ ${#pkgs[@]} -gt 0 ]]; then
        # Use array expansion for better argument passing
        uv pip install -Uq --system --no-break-system-packages --compile-bytecode --refresh "${pkgs[@]}" \
          &>/dev/null || log "⚠️${YLW}Failed to update packages${DEF}"
      else
        log "✅${GRN}All Python packages are up to date${DEF}"
      fi
    else
      log "⚠️${YLW}jq not found, using fallback method${DEF}"
      # Optimize by avoiding process substitution when possible
      uv pip install --upgrade -r <(uv pip list --format freeze) &>/dev/null \
        || log "⚠️${YLW}Failed to update packages${DEF}"
    fi

    log "🔄${BLU}Updating Python interpreters...${DEF}"
    uv python update-shell -q
    uv python upgrade -q || log "⚠️${YLW}Failed to update Python versions${DEF}"
  fi
}

update_system_utils() {
  log "🔄${BLU}Running miscellaneous updates...${DEF}"
  # Pre-filter commands that exist to reduce repeated has() calls
  local cmds=(
    "fc-cache:-f"
    "update-desktop-database:"
    "update-pciids:"
    "update-smart-drivedb:"
    "update-ccache-links:"
  )

  local cmd cmd_name cmd_args
  for cmd in "${cmds[@]}"; do
    cmd_name="${cmd%%:*}"
    cmd_args="${cmd#*:}"
    if has "$cmd_name"; then
      if [[ -n $cmd_args ]]; then
        run_priv "$cmd_name" "$cmd_args" &>/dev/null || :
      else
        run_priv "$cmd_name" &>/dev/null || :
      fi
    fi
  done

  has update-leap && LC_ALL=C update-leap &>/dev/null || :

  # Update firmware
  if has fwupdmgr; then
    log "🔄${BLU}Updating firmware...${DEF}"
    run_priv fwupdmgr refresh -y || :
    run_priv fwupdtool update || :
  fi
}

update_boot() {
  log "🔍${BLU}Checking boot configuration...${DEF}"
  # Update systemd-boot if installed
  if [[ -d /sys/firmware/efi ]] && has bootctl && run_priv bootctl is-installed -q &>/dev/null; then
    log "✅${GRN}systemd-boot detected, updating${DEF}"
    run_priv bootctl update -q &>/dev/null
    run_priv bootctl cleanup -q &>/dev/null
  else
    log "❌${YLW}systemd-boot not present, skipping${DEF}"
  fi

  # Update sdboot-manage if available
  if has sdboot-manage; then
    log "🔄${BLU}Updating sdboot-manage...${DEF}"
    run_priv sdboot-manage remove &>/dev/null || :
    run_priv sdboot-manage update &>/dev/null || :
  fi

  # Update initramfs
  log "🔄${BLU}Updating initramfs...${DEF}"
  if has update-initramfs; then
    run_priv update-initramfs
  else
    local found_initramfs=0
    for cmd in limine-mkinitcpio mkinitcpio dracut-rebuild; do
      if has "$cmd"; then
        if [[ $cmd == mkinitcpio ]]; then
          run_priv "$cmd" -P || :
        else
          run_priv "$cmd" || :
        fi
        found_initramfs=1
        break
      fi
    done

    # Special case for booster
    if [[ $found_initramfs -eq 0 && -x /usr/lib/booster/regenerate_images ]]; then
      run_priv /usr/lib/booster/regenerate_images || :
    elif [[ $found_initramfs -eq 0 ]]; then
      log "${YLW}No initramfs generator found, please update manually${DEF}"
    fi
  fi
}

run_update() {
  print_named_banner "update" "Meow (> ^ <)"
  setup_build_env

  checkupdates -dc &>/dev/null || :

  # Run basic system maintenance
  run_system_maintenance modprobed-db
  run_system_maintenance hwclock -w
  run_system_maintenance updatedb
  run_system_maintenance chwd -a
  run_system_maintenance mandb

  # Run update functions
  update_system_packages
  update_with_topgrade
  update_flatpak
  update_rust
  update_editors
  update_shells
  update_python
  update_system_utils
  update_boot
  log "\n${GRN}All done ✅ (> ^ <) Meow${DEF}\n"
}

#=========== Clean Functions ===========
# Clean arrays of file/directory paths
clean_paths() {
  local paths=("$@") path
  # Batch check existence to reduce syscalls
  local existing_paths=()
  for path in "${paths[@]}"; do
    # Handle wildcard paths
    if [[ $path == *\** ]]; then
      # Use globbing directly and collect existing items
      shopt -s nullglob
      # shellcheck disable=SC2206
      local -a items=($path)
      for item in "${items[@]}"; do
        [[ -e $item ]] && existing_paths+=("$item")
      done
      shopt -u nullglob
    else
      [[ -e $path ]] && existing_paths+=("$path")
    fi
  done
  # Batch delete all existing paths at once
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

clean_with_sudo() {
  local paths=("$@") path
  # Batch check existence to reduce syscalls and sudo invocations
  local existing_paths=()
  for path in "${paths[@]}"; do
    # Handle wildcard paths
    if [[ $path == *\** ]]; then
      # Use globbing directly and collect existing items
      shopt -s nullglob
      # shellcheck disable=SC2206
      local -a items=($path)
      for item in "${items[@]}"; do
        [[ -e $item ]] && existing_paths+=("$item")
      done
      shopt -u nullglob
    else
      [[ -e $path ]] && existing_paths+=("$path")
    fi
  done
  # Batch delete all existing paths at once with single sudo call
  [[ ${#existing_paths[@]} -gt 0 ]] && run_priv rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

run_clean() {
  print_named_banner "clean"

  # Ensure sudo access
  [[ $EUID -ne 0 && -n $SUDO ]] && "$SUDO" -v

  # Capture disk usage before cleanup
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(run_priv du -sh / 2>/dev/null | cut -f1)

  log "🔄${BLU}Starting system cleanup...${DEF}"

  # Drop caches
  sync
  log "🔄${BLU}Dropping cache...${DEF}"
  echo 3 | run_priv tee /proc/sys/vm/drop_caches &>/dev/null

  # Store and sort modprobed database
  if has modprobed-db; then
    log "🔄${BLU}Storing kernel modules...${DEF}"
    run_priv modprobed-db store

    local db_files=("${HOME}/.config/modprobed.db" "${HOME}/.local/share/modprobed.db")
    for db in "${db_files[@]}"; do
      [[ -f $db ]] && sort -u "$db" -o "$db" &>/dev/null || :
    done
  fi

  # Network cleanup
  log "🔄${BLU}Flushing network caches...${DEF}"
  has dhclient && dhclient -r &>/dev/null || :
  run_priv resolvectl flush-caches &>/dev/null || :

  # Package management cleanup
  log "🔄${BLU}Removing orphaned packages...${DEF}"
  # Optimized: Use pacman directly instead of array
  local orphans_list
  orphans_list=$(pacman -Qdtq 2>/dev/null || :)
  if [[ -n $orphans_list ]]; then
    # Use xargs to pass arguments efficiently
    printf '%s\n' "$orphans_list" | xargs -r run_priv pacman -Rns --noconfirm &>/dev/null || :
  fi

  log "🔄${BLU}Cleaning package cache...${DEF}"
  run_priv pacman -Scc --noconfirm &>/dev/null || :
  run_priv paccache -rk0 -q &>/dev/null || :

  # Python package manager cleanup
  if has uv; then
    log "🔄${BLU}Cleaning UV cache...${DEF}"
    uv cache prune -q 2>/dev/null || :
    uv cache clean -q 2>/dev/null || :
  fi

  # Cargo/Rust cleanup
  if has cargo-cache; then
    log "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg 2>/dev/null || :
    cargo cache -efg trim --limit 1B 2>/dev/null || :
    cargo cache -efg clean-unref 2>/dev/null || :
  fi

  # Kill CPU-intensive processes
  log "🔄${BLU}Checking for CPU-intensive processes...${DEF}"
  # Optimized: Use xargs instead of while-read loop for better performance
  ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && $3>50.0 {print $2}' | xargs -r run_priv kill -9 &>/dev/null || :

  # Reset swap
  log "🔄${BLU}Resetting swap space...${DEF}"
  run_priv swapoff -a &>/dev/null || :
  run_priv swapon -a &>/dev/null || :

  # Clean log files and crash dumps
  log "🔄${BLU}Cleaning logs and crash dumps...${DEF}"
  # Use fd if available, fallback to find - optimize with batch delete
  if has fd; then
    run_priv fd -H -t f -e log -d 4 --changed-before 7d . /var/log -X rm &>/dev/null || :
    run_priv fd -H -t f -p "core.*" -d 2 --changed-before 7d . /var/crash -X rm &>/dev/null || :
  else
    # Use -delete for better performance than -exec rm
    run_priv find /var/log/ -name "*.log" -type f -mtime +7 -delete &>/dev/null || :
    run_priv find /var/crash/ -name "core.*" -type f -mtime +7 -delete &>/dev/null || :
  fi
  run_priv find /var/cache/apt/ -name "*.bin" -mtime +7 -delete &>/dev/null || :

  # Clean cache files
  log "🔄${BLU}Cleaning cache files...${DEF}"
  local cache_dirs=(
    "/var/cache/"
    "/tmp/"
    "/var/tmp/"
    "/var/crash/"
    "/var/lib/systemd/coredump/"
    "${HOME}/.cache/"
    "/root/.cache/"
  )

  # Clean user cache - optimize by using -delete directly with find
  if has fd; then
    # Use fd with batch delete for better performance
    fd -H -t f -d 4 --changed-before 1d . "${HOME}/.cache" -X rm &>/dev/null || :
    fd -H -t d -d 4 --changed-before 1d -E "**/.git" . "${HOME}/.cache" -X rmdir &>/dev/null || :
  else
    # find -delete is more efficient than -exec rm
    find "${HOME}/.cache" -type f -mtime +1 -delete &>/dev/null || :
    find "${HOME}/.cache" -type d -empty -delete &>/dev/null || :
  fi

  run_priv systemd-tmpfiles --clean &>/dev/null || :

  # Clean system and user cache directories
  clean_with_sudo "${cache_dirs[@]/%/*}"

  # Clean Flatpak application caches
  clean_paths "${HOME}/.var/app/"*/cache/* 2>/dev/null || :

  # Clean Qt cache files
  clean_paths "${HOME}/.config/Trolltech.conf" 2>/dev/null || :

  # Rebuild KDE cache if present
  has kbuildsycoca6 && kbuildsycoca6 --noincremental &>/dev/null || :

  # Empty trash directories
  log "🔄${BLU}Emptying trash...${DEF}"
  local trash_dirs=(
    "${HOME}/.local/share/Trash/"
    "/root/.local/share/Trash/"
  )
  clean_paths "${trash_dirs[@]/%/*}" 2>/dev/null || :

  # Flatpak cleanup
  if has flatpak; then
    log "🔄${BLU}Cleaning Flatpak...${DEF}"
    flatpak uninstall --unused --delete-data -y --noninteractive &>/dev/null || :

    # Clean flatpak caches
    local flatpak_dirs=(
      "/var/tmp/flatpak-cache-"
      "${HOME}/.cache/flatpak/system-cache/"
      "${HOME}/.local/share/flatpak/system-cache/"
      "${HOME}/.var/app/*/data/Trash/"
    )
    clean_paths "${flatpak_dirs[@]}" 2>/dev/null || :
  fi

  # Clear thumbnails
  clean_paths "${HOME}/.thumbnails/" 2>/dev/null || :

  # Clean system logs
  log "🔄${BLU}Cleaning system logs...${DEF}"
  run_priv rm -f --preserve-root -- /var/log/pacman.log &>/dev/null || :
  run_priv journalctl --rotate --vacuum-size=1 --flush --sync -q &>/dev/null || :
  clean_with_sudo /run/log/journal/* /var/log/journal/* /root/.local/share/zeitgeist/* /home/*/.local/share/zeitgeist/* 2>/dev/null || :

  # Clean history files
  log "🔄${BLU}Cleaning history files...${DEF}"
  local history_files=(
    "${HOME}/.wget-hsts"
    "${HOME}/.curl-hsts"
    "${HOME}/.lesshst"
    "${HOME}/nohup.out"
    "${HOME}/token"
    "${HOME}/.local/share/fish/fish_history"
    "${HOME}/.config/fish/fish_history"
    "${HOME}/.zsh_history"
    "${HOME}/.bash_history"
    "${HOME}/.history"
  )

  local root_history_files=(
    "/root/.local/share/fish/fish_history"
    "/root/.config/fish/fish_history"
    "/root/.zsh_history"
    "/root/.bash_history"
    "/root/.history"
  )

  clean_paths "${history_files[@]}" 2>/dev/null || :
  clean_with_sudo "${root_history_files[@]}" 2>/dev/null || :

  # Application-specific cleanups
  log "🔄${BLU}Cleaning application caches...${DEF}"

  # LibreOffice
  local libreoffice_paths=(
    "${HOME}/.config/libreoffice/4/user/registrymodifications.xcu"
    "${HOME}/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"
    "${HOME}/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu"
  )
  clean_paths "${libreoffice_paths[@]}" 2>/dev/null || :

  # Steam
  local steam_paths=(
    "${HOME}/.local/share/Steam/appcache/"
    "${HOME}/snap/steam/common/.cache/"
    "${HOME}/snap/steam/common/.local/share/Steam/appcache/"
    "${HOME}/.var/app/com.valvesoftware.Steam/cache/"
    "${HOME}/.var/app/com.valvesoftware.Steam/data/Steam/appcache/"
  )
  clean_paths "${steam_paths[@]/%/*}" 2>/dev/null || :

  # NVIDIA
  run_priv rm -rf --preserve-root -- "${HOME}/.nv/ComputeCache/"* &>/dev/null || :

  # Python history
  log "🔄${BLU}Securing Python history...${DEF}"
  local python_history="${HOME}/.python_history"
  [[ ! -f $python_history ]] && { touch "$python_history" 2>/dev/null || :; }
  run_priv chattr +i "$(realpath "$python_history")" &>/dev/null || :

  # Firefox cleanup
  log "🔄${BLU}Cleaning Firefox...${DEF}"
  local firefox_paths=(
    "${HOME}/.mozilla/firefox/*/bookmarkbackups"
    "${HOME}/.mozilla/firefox/*/saved-telemetry-pings"
    "${HOME}/.mozilla/firefox/*/sessionstore-logs"
    "${HOME}/.mozilla/firefox/*/sessionstore-backups"
    "${HOME}/.cache/mozilla/"
    "${HOME}/.var/app/org.mozilla.firefox/cache/"
    "${HOME}/snap/firefox/common/.cache/"
  )
  clean_paths "${firefox_paths[@]}" 2>/dev/null || :

  # Firefox crashes with Python - fixed heredoc format
  if has python3; then
    python3 <<'EOF' &>/dev/null
import glob, os
for pattern in ['~/.mozilla/firefox/*/crashes/*', '~/.mozilla/firefox/*/crashes/events/*']:
  for path in glob.glob(os.path.expanduser(pattern)):
    if os.path.isfile(path):
      try: os.remove(path)
      except: pass
EOF
  fi

  # Wine cleanup
  log "🔄${BLU}Cleaning Wine...${DEF}"
  local wine_paths=(
    "${HOME}/.wine/drive_c/windows/temp/"
    "${HOME}/.cache/wine/"
    "${HOME}/.cache/winetricks/"
  )
  clean_paths "${wine_paths[@]/%/*}" 2>/dev/null || :

  # GTK recent files
  local gtk_paths=(
    "/.recently-used.xbel"
    "${HOME}/.local/share/recently-used.xbel"
    "${HOME}/snap/*/*/.local/share/recently-used.xbel"
    "${HOME}/.var/app/*/data/recently-used.xbel"
  )
  clean_paths "${gtk_paths[@]}" 2>/dev/null || :

  # KDE recent files
  local kde_paths=(
    "${HOME}/.local/share/RecentDocuments/*.desktop"
    "${HOME}/.kde/share/apps/RecentDocuments/*.desktop"
    "${HOME}/.kde4/share/apps/RecentDocuments/*.desktop"
    "${HOME}/.var/app/*/data/*.desktop"
  )
  clean_paths "${kde_paths[@]}" 2>/dev/null || :

  # Trim disks
  log "🔄${BLU}Trimming disks...${DEF}"
  run_priv fstrim -a --quiet-unsupported &>/dev/null || :
  run_priv fstrim -A --quiet-unsupported &>/dev/null || :

  # Rebuild font cache
  log "🔄${BLU}Rebuilding font cache...${DEF}"
  run_priv fc-cache -f &>/dev/null || :

  # SDK cleanup
  has sdk && sdk flush tmp &>/dev/null || :

  # BleachBit if available
  if has bleachbit; then
    log "🔄${BLU}Running BleachBit...${DEF}"
    LC_ALL=C LANG=C bleachbit -c --preset &>/dev/null || :

    # Run with elevated privileges if possible
    if has xhost; then
      xhost si:localuser:root &>/dev/null || :
      xhost si:localuser:"$USER" &>/dev/null || :
      LC_ALL=C LANG=C run_priv bleachbit -c --preset &>/dev/null || :
    elif has pkexec; then
      LC_ALL=C LANG=C pkexec bleachbit -c --preset &>/dev/null || :
    else
      log "⚠️${YLW}Cannot run BleachBit with elevated privileges${DEF}"
    fi
  fi

  # Show disk usage results
  log "${GRN}System cleaned!${DEF}"
  capture_disk_usage disk_after
  space_after=$(run_priv du -sh / 2>/dev/null | cut -f1)

  log "==> ${BLU}Disk usage before cleanup:${DEF} ${disk_before}"
  log "==> ${GRN}Disk usage after cleanup: ${DEF} ${disk_after}"
  log
  log "${BLU}Space before/after:${DEF}"
  log "${YLW}Before:${DEF} ${space_before}"
  log "${GRN}After: ${DEF} ${space_after}"
}

#=========== Traps & Cleanup ===========
# Enhanced cleanup for archmaint
cleanup_archmaint() {
  cleanup_pacman_lock
  # Reset environment variables
  unset LC_ALL RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
}

trap cleanup_archmaint EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#=========== CLI Interface =============
show_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] COMMAND

Arch Linux system maintenance script for updating and cleaning.

Commands:
  update    Update system packages and components
  clean     Clean system caches and temporary files

Options:
  -h, --help       Show this help message
  -q, --quiet      Suppress normal output
  -v, --verbose    Enable verbose output
  -y, --yes        Answer yes to all prompts
  -n, --dry-run    Show what would be done without making changes

Examples:
  $(basename "$0") update         # Update system packages and components
  $(basename "$0") clean          # Clean system caches and temporary files
  $(basename "$0") -y clean       # Clean without prompting
  $(basename "$0") -qn update     # Quiet dry-run update
EOF
}

parse_args() {
  # Process options
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
      show_usage exit 0
      ;;
    -q | --quiet) QUIET=1 shift ;;
    -v | --verbose) VERBOSE=1 shift ;;
    -y | --yes) ASSUME_YES=1 shift ;;
    -n | --dry-run) DRYRUN=1 shift ;;
    update | clean)
      [[ -n $MODE ]] && die "Cannot specify multiple commands: $MODE and $1"
      MODE=$1 shift
      ;;
    *) die "Unknown option: $1\nUse --help for usage information." ;;
    esac
  done
  # Validate command
  if [[ -z $MODE ]]; then
    die "No command specified. Use 'update' or 'clean'.\nUse --help for usage information."
  fi
}

#=========== Main Function =============
main() {
  parse_args "$@"
  if [[ $DRYRUN -eq 1 ]]; then
    log "${YLW}Running in dry-run mode. No changes will be made.${DEF}"
  fi
  case "$MODE" in
  update) run_update ;;
  clean) run_clean ;;
  *) die "Unknown command: $MODE" ;;
  esac
}
main "$@"
