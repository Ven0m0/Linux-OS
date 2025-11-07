#!/usr/bin/env bash
# Common library for Linux-OS bash scripts
# Provides shared functions, color definitions, and utilities
# Source this file in your scripts: source "${BASH_SOURCE%/*}/lib/common.sh" || exit 1

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Export common locale settings
export LC_ALL=C LANG=C LANGUAGE=C

#============ Color & Effects ============
# Trans flag color palette (LBLU → PNK → BWHT → PNK → LBLU)
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Export color variables so they're available to sourcing scripts
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD

#============ Core Helper Functions ============
# Check if command exists
has() { command -v "$1" &>/dev/null; }

# Echo with formatting support
xecho() { printf '%b\n' "$*"; }

# Logging functions
log() { xecho "$*"; }
err() { xecho "$*" >&2; }
die() {
  err "${RED}Error:${DEF} $*"
  exit 1
}

# Confirmation prompt
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#============ Privilege Escalation ============
# Detect available privilege escalation tool
get_priv_cmd() {
  local cmd
  for cmd in sudo-rs sudo doas; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  [[ $EUID -eq 0 ]] || die "No privilege tool found (sudo-rs/sudo/doas) and not running as root"
  printf ''
}

# Initialize privilege tool
init_priv() {
  local priv_cmd
  priv_cmd=$(get_priv_cmd)
  [[ -n $priv_cmd && $EUID -ne 0 ]] && "$priv_cmd" -v
  printf '%s' "$priv_cmd"
}

# Run command with privilege escalation
run_priv() {
  local priv_cmd="${PRIV_CMD:-}"
  if [[ -z $priv_cmd ]]; then
    priv_cmd=$(get_priv_cmd)
  fi
  
  if [[ $EUID -eq 0 || -z $priv_cmd ]]; then
    "$@"
  else
    "$priv_cmd" -- "$@"
  fi
}

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner() {
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  
  mapfile -t lines <<<"$banner"
  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  
  if ((line_count <= 1)); then
    for line in "${lines[@]}"; do
      printf '%s%s%s\n' "${flag_colors[0]}" "$line" "$DEF"
    done
  else
    for i in "${!lines[@]}"; do
      local segment_index=$((i * (segments - 1) / (line_count - 1)))
      ((segment_index >= segments)) && segment_index=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
    done
  fi
  
  [[ -n $title ]] && xecho "$title"
}

# Pre-defined banners
get_update_banner() {
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}

get_clean_banner() {
  cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}

# Print predefined banner
# Usage: print_named_banner "update"|"clean" [title]
print_named_banner() {
  local name="$1" title="${2:-Meow (> ^ <)}"
  local banner
  
  case "$name" in
  update) banner=$(get_update_banner) ;;
  clean) banner=$(get_clean_banner) ;;
  *) die "Unknown banner name: $name" ;;
  esac
  
  print_banner "$banner" "$title"
}

#============ Build Environment Setup ============
# Setup optimized build environment for Arch Linux
setup_build_env() {
  export HOME="${HOME:-/home/${SUDO_USER:-$USER}}"
  export SHELL="${SHELL:-/bin/bash}"
  
  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
  
  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  
  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
  
  # Cargo configuration
  export CARGO_CACHE_RUSTC_INFO=1
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  export RUSTC_BOOTSTRAP=1
  
  # Parallel build settings
  local nproc_count
  nproc_count=$(nproc 2>/dev/null || echo 4)
  export MAKEFLAGS="-j${nproc_count}"
  export NINJAFLAGS="-j${nproc_count}"
  
  # Compiler selection (prefer LLVM toolchain)
  if has clang && has clang++; then
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export NM=llvm-nm
    export RANLIB=llvm-ranlib
    
    # Use lld linker if available
    if has ld.lld; then
      export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
    fi
  fi
  
  # Initialize dbus if available
  has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"
}

#============ Common Cleanup Patterns ============
# Remove pacman database lock
cleanup_pacman_lock() {
  [[ -f /var/lib/pacman/db.lck ]] && run_priv rm -f -- /var/lib/pacman/db.lck &>/dev/null || :
}

# Generic cleanup function for use with trap
cleanup_generic() {
  cleanup_pacman_lock
}

# Setup standard cleanup trap
setup_cleanup_trap() {
  trap cleanup_generic EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance() {
  local cmd=$1
  shift
  local args=("$@")
  
  has "$cmd" || return 0
  
  case "$cmd" in
  modprobed-db)
    "$cmd" store &>/dev/null || :
    ;;
  hwclock | updatedb | chwd)
    run_priv "$cmd" "${args[@]}" &>/dev/null || :
    ;;
  mandb)
    run_priv "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :
    ;;
  *)
    run_priv "$cmd" "${args[@]}" &>/dev/null || :
    ;;
  esac
}

#============ Disk Usage Helpers ============
# Capture current disk usage
capture_disk_usage() {
  local var_name=$1
  local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

#============ File Finding Helpers ============
# Use fd if available, fallback to find
find_files() {
  if has fd && [[ ! " $* " =~ " --exec " ]]; then
    fd -H --color=never "$@"
  else
    find "$@"
  fi
}

# NUL-safe finder using fd/fdf/find
find0() {
  local root=$1
  shift
  if has fdf; then
    fdf -H -0 --color=never "$@" . "$root"
  elif has fd; then
    fd -H -0 --color=never "$@" . "$root"
  else
    find "$root" "$@" -print0
  fi
}

#============ Package Manager Detection ============
# Detect and return best available AUR helper or pacman
# Cache result to avoid repeated checks
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()

detect_pkg_manager() {
  # Return cached result if available
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

#============ SQLite Maintenance ============
# Vacuum a single SQLite database and return bytes saved
vacuum_sqlite() {
  local db=$1 s_old s_new
  [[ -f $db ]] || { printf '0\n'; return; }
  # Skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0\n'; return; }
  s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0\n'; return; }
  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || { printf '0\n'; return; }
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}

# Clean SQLite databases in current working directory
clean_sqlite_dbs() {
  local total=0 db saved
  # Batch file type checks to reduce subprocess calls
  while IFS= read -r -d '' db; do
    # Skip non-regular files early
    [[ -f $db ]] || continue
    # Use magic byte check instead of spawning file command
    if head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then
      saved=$(vacuum_sqlite "$db" || printf '0')
      ((saved > 0)) && total=$((total + saved))
    fi
  done < <(find0 . -maxdepth 1 -type f)
  ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}

#============ Process Management ============
# Wait for processes to exit, kill if timeout
ensure_not_running_any() {
  local timeout=6 p running_procs=()
  # Batch check all processes once instead of individually
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && running_procs+=("$p")
  done
  
  # Only process running programs
  [[ ${#running_procs[@]} -eq 0 ]] && return
  
  for p in "${running_procs[@]}"; do
    printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
    local wait_time=$timeout
    while ((wait_time-- > 0)) && pgrep -x -u "$USER" "$p" &>/dev/null; do
      sleep 1
    done
    pgrep -x -u "$USER" "$p" &>/dev/null && {
      printf '  %s\n' "${RED}Killing ${p}...${DEF}"
      pkill -KILL -x -u "$USER" "$p" &>/dev/null || :
      sleep 1
    }
  done
}

#============ Browser Profile Detection ============
# Firefox-family profile discovery
foxdir() {
  local base=$1 p
  [[ -d $base ]] || return 1
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi
  if [[ -f $base/profiles.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi
  return 1
}

# List all Mozilla profiles in a base directory
mozilla_profiles() {
  local base=$1 p
  declare -A seen
  [[ -d $base ]] || return 0
  
  # Process installs.ini using awk for efficiency
  if [[ -f $base/installs.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini")
  fi
  
  # Process profiles.ini using awk for efficiency
  if [[ -f $base/profiles.ini ]]; then
    while IFS= read -r p; do
      [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }
    done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini")
  fi
}

# Chromium roots (native/flatpak/snap)
chrome_roots_for() {
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    *) : ;;
  esac
}

# List Default + Profile * dirs under a Chromium root
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
}

#============ Path Cleaning Helpers ============
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

# Clean paths with privilege escalation
clean_with_sudo() {
  local paths=("$@") path
  # Batch check existence to reduce syscalls and sudo invocations
  local existing_paths=()
  for path in "${paths[@]}"; do
    # Handle wildcard paths
    if [[ $path == *\** ]]; then
      # Use globbing directly and collect existing items
      shopt -s nullglob
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

# Library successfully loaded
return 0
