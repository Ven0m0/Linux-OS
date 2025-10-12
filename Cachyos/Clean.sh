#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar execfail
export LC_ALL=C LANG=C LANGUAGE=C

#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

#──────────── Helpers ────────────────────
has() { command -v "$1" >/dev/null 2>&1; }
xecho() { printf '%b\n' "$*"; }
confirm() {
  local msg=${1:-Proceed?} ans
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#──────────── Privilege Helper ──────────
get_priv_cmd() {
  local cmd
  for cmd in sudo-rs sudo doas; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  [[ $EUID -eq 0 ]] && printf '%s' "" || { xecho "${RED}No privilege tool found${DEF}" >&2; exit 1; }
}

PRIV_CMD=$(get_priv_cmd)
[[ -n $PRIV_CMD && $EUID -ne 0 ]] && "$PRIV_CMD" -v

run_priv() {
  [[ $EUID -eq 0 || -z $PRIV_CMD ]] && "$@" || "$PRIV_CMD" -- "$@"
}

#──────────── Banner ────────────────────
print_banner() {
  local banner flag_colors
  banner=$(cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ 
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ 
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
)
  mapfile -t lines <<<"$banner"
  flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  
  if ((line_count <= 1)); then
    for line in "${lines[@]}"; do
      printf '%s%s%s\n' "${flag_colors[0]}" "$line" "$DEF"
    done
  else
    for i in "${!lines[@]}"; do
      local segment_index=$(( i * (segments - 1) / (line_count - 1) ))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
    done
  fi
}

#──────────── Cleanup & Exit Traps ──────
cleanup() { :; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#──────────── Path Arrays ────────────────
# Define path arrays for cleanup operations
declare -a CACHE_DIRS=(
  "/var/cache/"
  "/tmp/"
  "/var/tmp/"
  "/var/crash/"
  "/var/lib/systemd/coredump/"
  "${HOME:-/home/$USER}/.cache/"
  "/root/.cache/"
)

declare -a TRASH_DIRS=(
  "${HOME:-/home/$USER}/.local/share/Trash/"
  "/root/.local/share/Trash/"
)

declare -a FLATPAK_DIRS=(
  "/var/tmp/flatpak-cache-"
  "${HOME:-/home/$USER}/.cache/flatpak/system-cache/"
  "${HOME:-/home/$USER}/.local/share/flatpak/system-cache/"
  "${HOME:-/home/$USER}/.var/app/*/data/Trash/"
)

declare -a HISTORY_FILES=(
  "${HOME:-/home/$USER}/.wget-hsts"
  "${HOME:-/home/$USER}/.curl-hsts"
  "${HOME:-/home/$USER}/.lesshst"
  "${HOME:-/home/$USER}/nohup.out"
  "${HOME:-/home/$USER}/token"
  "${HOME:-/home/$USER}/.local/share/fish/fish_history"
  "${HOME:-/home/$USER}/.config/fish/fish_history"
  "${HOME:-/home/$USER}/.zsh_history"
  "${HOME:-/home/$USER}/.bash_history"
  "${HOME:-/home/$USER}/.history"
)

declare -a ROOT_HISTORY_FILES=(
  "/root/.local/share/fish/fish_history"
  "/root/.config/fish/fish_history"
  "/root/.zsh_history"
  "/root/.bash_history"
  "/root/.history"
)

declare -a LIBREOFFICE_PATHS=(
  "${HOME:-/home/$USER}/.config/libreoffice/4/user/registrymodifications.xcu"
  "${HOME:-/home/$USER}/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu"
  "${HOME:-/home/$USER}/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu"
)

declare -a STEAM_DIRS=(
  "${HOME:-/home/$USER}/.local/share/Steam/appcache/"
  "${HOME:-/home/$USER}/snap/steam/common/.cache/"
  "${HOME:-/home/$USER}/snap/steam/common/.local/share/Steam/appcache/"
  "${HOME:-/home/$USER}/.var/app/com.valvesoftware.Steam/cache/"
  "${HOME:-/home/$USER}/.var/app/com.valvesoftware.Steam/data/Steam/appcache/"
)

declare -a FIREFOX_DIRS=(
  "${HOME:-/home/$USER}/.mozilla/firefox/*/bookmarkbackups"
  "${HOME:-/home/$USER}/.mozilla/firefox/*/saved-telemetry-pings"
  "${HOME:-/home/$USER}/.mozilla/firefox/*/sessionstore-logs"
  "${HOME:-/home/$USER}/.mozilla/firefox/*/sessionstore-backups"
  "${HOME:-/home/$USER}/.cache/mozilla/"
  "${HOME:-/home/$USER}/.var/app/org.mozilla.firefox/cache/"
  "${HOME:-/home/$USER}/snap/firefox/common/.cache/"
)

declare -a WINE_DIRS=(
  "${HOME:-/home/$USER}/.wine/drive_c/windows/temp/"
  "${HOME:-/home/$USER}/.cache/wine/"
  "${HOME:-/home/$USER}/.cache/winetricks/"
)

declare -a GTK_PATHS=(
  "/.recently-used.xbel"
  "${HOME:-/home/$USER}/.local/share/recently-used.xbel"
  "${HOME:-/home/$USER}/snap/*/*/.local/share/recently-used.xbel"
  "${HOME:-/home/$USER}/.var/app/*/data/recently-used.xbel"
)

declare -a KDE_PATHS=(
  "${HOME:-/home/$USER}/.local/share/RecentDocuments/*.desktop"
  "${HOME:-/home/$USER}/.kde/share/apps/RecentDocuments/*.desktop"
  "${HOME:-/home/$USER}/.kde4/share/apps/RecentDocuments/*.desktop"
  "${HOME:-/home/$USER}/.var/app/*/data/*.desktop"
)

#──────────── Main Functions ────────────
# Function to safely remove files/directories
safe_remove() {
  local target=$1
  [[ -e $target ]] && rm -rf --preserve-root -- "$target" >/dev/null 2>&1 || :
}

# Function to clean multiple paths
clean_paths() {
  local paths=("$@")
  for path in "${paths[@]}"; do
    # Handle wildcard paths
    if [[ $path == *\** ]]; then
      # Use globbing directly
      for item in $path; do
        [[ -e $item ]] && safe_remove "$item"
      done
    else
      [[ -e $path ]] && safe_remove "$path"
    fi
  done
}

# Function to remove file patterns with sudo
sudo_clean_paths() {
  local paths=("$@")
  for path in "${paths[@]}"; do
    # Handle wildcard paths
    if [[ $path == *\** ]]; then
      # Use globbing directly
      for item in $path; do
        [[ -e $item ]] && run_priv rm -rf --preserve-root -- "$item" >/dev/null 2>&1 || :
      done
    else
      [[ -e $path ]] && run_priv rm -rf --preserve-root -- "$path" >/dev/null 2>&1 || :
    fi
  done
}

# Function to run a command with error suppression
run_quiet() {
  "$@" >/dev/null 2>&1 || :
}

capture_disk_usage() {
  local var_name=$1
  local -n ref=$var_name
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

main() {
  print_banner
  
  # Ensure sudo access
  [[ $EUID -ne 0 ]] && run_priv true
  export HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
  
  # Capture disk usage before cleanup
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(run_priv du -sh / 2>/dev/null | cut -f1)
  
  # Drop caches
  sync
  xecho "🔄${BLU}Dropping cache...${DEF}"
  echo 3 | run_priv tee /proc/sys/vm/drop_caches >/dev/null 2>&1
  
  # Store and sort modprobed database
  if has modprobed-db; then
    xecho "🔄${BLU}Storing kernel modules...${DEF}"
    run_priv modprobed-db store
    
    local db_files=("${HOME}/.config/modprobed.db" "${HOME}/.local/share/modprobed.db")
    for db in "${db_files[@]}"; do
      [[ -f $db ]] && sort -u "$db" -o "$db" >/dev/null 2>&1 || :
    done
  fi
  
  # Network cleanup
  xecho "🔄${BLU}Flushing network caches...${DEF}"
  has dhclient && run_quiet dhclient -r
  run_priv resolvectl flush-caches >/dev/null 2>&1 || :
  
  # Package management cleanup
  xecho "🔄${BLU}Removing orphaned packages...${DEF}"
  local orphans
  orphans=$(pacman -Qdtq 2>/dev/null || echo)
  if [[ -n $orphans ]]; then
    run_priv pacman -Rns $orphans --noconfirm >/dev/null 2>&1 || :
  fi
  
  xecho "🔄${BLU}Cleaning package cache...${DEF}"
  run_priv pacman -Scc --noconfirm >/dev/null 2>&1 || :
  run_priv paccache -rk0 -q >/dev/null 2>&1 || :
  
  # Python package manager cleanup
  if has uv; then
    xecho "🔄${BLU}Cleaning UV cache...${DEF}"
    uv cache prune -q
    uv cache clean -q
  fi
  
  # Cargo/Rust cleanup
  if has cargo-cache; then
    xecho "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg >/dev/null 2>&1 || :
    cargo cache -efg trim --limit 1B >/dev/null 2>&1 || :
    cargo cache -efg clean-unref >/dev/null 2>&1 || :
  fi
  
  # Kill CPU-intensive processes
  xecho "🔄${BLU}Checking for CPU-intensive processes...${DEF}"
  while read -r pid; do
    [[ -n $pid ]] && run_priv kill -9 "$pid" >/dev/null 2>&1 || :
  done < <(ps aux --sort=-%cpu 2>/dev/null | awk '{if($3>50.0) print $2}' | tail -n +2)
  
  # Reset swap
  xecho "🔄${BLU}Resetting swap space...${DEF}"
  run_priv swapoff -a >/dev/null 2>&1 || :
  run_priv swapon -a >/dev/null 2>&1 || :
  
  # Clean log files and crash dumps
  xecho "🔄${BLU}Cleaning logs and crash dumps...${DEF}"
  if has fd; then
    run_priv fd -H -t f -e log -d 4 --changed-before 7d . /var/log -x rm {} \; >/dev/null 2>&1 || :
    run_priv fd -H -t f -p "core.*" -d 2 --changed-before 7d . /var/crash -x rm {} \; >/dev/null 2>&1 || :
  else
    run_priv find -O3 /var/log/ -name "*.log" -type f -mtime +7 -delete >/dev/null 2>&1 || :
    run_priv find -O3 /var/crash/ -name "core.*" -type f -mtime +7 -delete >/dev/null 2>&1 || :
  fi
  run_priv find -O3 /var/cache/apt/ -name "*.bin" -mtime +7 -delete >/dev/null 2>&1 || :
  
  # Clean user cache
  xecho "🔄${BLU}Cleaning user cache...${DEF}"
  if has fd; then
    run_quiet fd -H -t f -d 4 --changed-before 1d . "${HOME}/.cache" -x rm {} \;
    run_quiet fd -H -t d -d 4 --changed-before 1d -E "**/.git" . "${HOME}/.cache" -x rmdir {} \;
  else
    run_quiet find -O3 "${HOME}/.cache" -type f -mtime +1 -delete
    run_quiet find -O3 "${HOME}/.cache" -type d -empty -delete
  fi
  
  run_priv systemd-tmpfiles --clean >/dev/null 2>&1 || :
  
  # Clean cache directories
  xecho "🔄${BLU}Cleaning system caches...${DEF}"
  sudo_clean_paths "${CACHE_DIRS[@]/%/*}"
  
  # Clean Flatpak application caches
  safe_remove "${HOME}/.var/app/"*/cache/*
  
  # Clean Qt cache files
  safe_remove "${HOME}/.config/Trolltech.conf"
  
  # Rebuild KDE cache if present
  has kbuildsycoca6 && run_quiet kbuildsycoca6 --noincremental
  
  # Empty trash directories
  xecho "🔄${BLU}Emptying trash...${DEF}"
  clean_paths "${TRASH_DIRS[@]/%/*}"
  
  # Flatpak cleanup
  if has flatpak; then
    xecho "🔄${BLU}Cleaning Flatpak...${DEF}"
    run_quiet flatpak uninstall --unused --delete-data -y --noninteractive
    
    # Clean flatpak caches
    clean_paths "${FLATPAK_DIRS[@]}"
  fi
  
  # Clear thumbnails
  xecho "🔄${BLU}Clearing thumbnails...${DEF}"
  safe_remove "${HOME}/.thumbnails/"
  
  # Clean system logs
  xecho "🔄${BLU}Cleaning system logs...${DEF}"
  run_priv rm -f --preserve-root -- /var/log/pacman.log >/dev/null 2>&1 || :
  run_priv journalctl --rotate --vacuum-size=1 --flush --sync -q >/dev/null 2>&1 || :
  sudo_clean_paths /run/log/journal/* /var/log/journal/* /root/.local/share/zeitgeist/* /home/*/.local/share/zeitgeist/*
  
  # Clean history files
  xecho "🔄${BLU}Cleaning history files...${DEF}"
  clean_paths "${HISTORY_FILES[@]}"
  sudo_clean_paths "${ROOT_HISTORY_FILES[@]}"
  
  # Application-specific cleanups
  xecho "🔄${BLU}Cleaning application caches...${DEF}"
  
  # LibreOffice
  clean_paths "${LIBREOFFICE_PATHS[@]}"
  
  # Steam
  clean_paths "${STEAM_DIRS[@]/%/*}"
  
  # NVIDIA
  run_priv rm -rf --preserve-root -- "${HOME}/.nv/ComputeCache/"* >/dev/null 2>&1 || :
  
  # Python history
  xecho "🔄${BLU}Securing Python history...${DEF}"
  local python_history="${HOME}/.python_history"
  [[ ! -f $python_history ]] && { touch "$python_history" || :; }
  run_priv chattr +i "$(realpath "$python_history")" >/dev/null 2>&1 || :
  
  # Firefox cleanup
  xecho "🔄${BLU}Cleaning Firefox...${DEF}"
  clean_paths "${FIREFOX_DIRS[@]}"
  
  # Firefox crashes with Python
  if has python3; then
    python3 <<EOF
import glob, os
for pattern in ['~/.mozilla/firefox/*/crashes/*', '~/.mozilla/firefox/*/crashes/events/*']:
  for path in glob.glob(os.path.expanduser(pattern)):
    if os.path.isfile(path):
      try: os.remove(path)
      except: pass
EOF
  fi
  
  # Wine cleanup
  xecho "🔄${BLU}Cleaning Wine...${DEF}"
  clean_paths "${WINE_DIRS[@]/%/*}"
  
  # GTK recent files
  clean_paths "${GTK_PATHS[@]}"
  
  # KDE recent files
  clean_paths "${KDE_PATHS[@]}"
  
  # Trim disks
  xecho "🔄${BLU}Trimming disks...${DEF}"
  run_priv fstrim -a --quiet-unsupported >/dev/null 2>&1 || :
  run_priv fstrim -A --quiet-unsupported >/dev/null 2>&1 || :
  
  # Rebuild font cache
  xecho "🔄${BLU}Rebuilding font cache...${DEF}"
  run_priv fc-cache -f >/dev/null 2>&1 || :
  
  # SDK cleanup
  has sdk && run_quiet sdk flush tmp
  
  # BleachBit if available
  if has bleachbit; then
    xecho "🔄${BLU}Running BleachBit...${DEF}"
    LC_ALL=C LANG=C run_quiet bleachbit -c --preset
    
    # Run with elevated privileges if possible
    if has xhost; then
      run_quiet xhost si:localuser:root
      run_quiet xhost si:localuser:"$USER"
      LC_ALL=C LANG=C run_priv bleachbit -c --preset >/dev/null 2>&1 || :
    elif has pkexec; then
      LC_ALL=C LANG=C run_quiet pkexec bleachbit -c --preset
    else
      xecho "⚠️${YLW}Cannot run BleachBit with elevated privileges${DEF}"
    fi
  fi
  
  # Show disk usage results
  xecho "${GRN}System cleaned!${DEF}"
  capture_disk_usage disk_after
  space_after=$(run_priv du -sh / 2>/dev/null | cut -f1)
  
  xecho "==> ${BLU}Disk usage before cleanup:${DEF} ${disk_before}"
  xecho "==> ${GRN}Disk usage after cleanup: ${DEF} ${disk_after}"
  xecho 
  xecho "${BLU}Space before/after:${DEF}"
  xecho "${YLW}Before:${DEF} ${space_before}"
  xecho "${GRN}After: ${DEF} ${space_after}"
}

main "$@"
