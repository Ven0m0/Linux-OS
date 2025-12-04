#!/usr/bin/env bash
# Core shared library for Linux-OS scripts
# This library provides common functions, colors, and utilities
# Usage: source "${SCRIPT_DIR}/../lib/core.sh" || exit 1

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar extglob dotglob

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
has() { command -v -- "$1" &>/dev/null; }

# Get command path/name
hasname() {
  local cmd=${1:?}
  if has "$cmd"; then
    command -v "$cmd"
    return 0
  fi
  return 1
}

# Echo with formatting support
xecho() { printf '%b\n' "$*"; }

# Logging functions
log() { xecho "$*"; }
msg() { xecho "$*"; }
warn() { xecho "${YLW}WARN:${DEF} $*" >&2; }
err() { xecho "${RED}ERROR:${DEF} $*" >&2; }
die() {
  err "$*"
  exit "${2:-1}"
}

# Debug logging (enabled by DEBUG=1)
dbg() { [[ ${DEBUG:-0} -eq 1 ]] && xecho "[DBG] $*" || :; }

# Confirmation prompt
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner() {
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")

  # Optimized: Use read loop instead of mapfile to avoid subprocess
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
  done <<< "$banner"

  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  if ((line_count <= 1)); then
    printf '%s%s%s\n' "${flag_colors[0]}" "${lines[0]}" "$DEF"
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
  cat << 'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}

get_clean_banner() {
  cat << 'EOF'
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
  local name="$1" title="${2:-Meow (> ^ <)}" banner
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
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null
  # Rust optimization flags
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
  # C/C++ optimization flags
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  # Linker optimization flags
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
  # Cargo configuration
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1
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

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance() {
  local cmd=$1
  shift
  local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in
    modprobed-db) "$cmd" store &>/dev/null || : ;;
    hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &>/dev/null || : ;;
    mandb) sudo "$cmd" -q &>/dev/null || mandb -q &>/dev/null || : ;;
    *) sudo "$cmd" "${args[@]}" &>/dev/null || : ;;
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
# Use fd/fdfind if available, fallback to find
# Usage: find_files <pattern> <array_var_name>
find_files() {
  local pattern=$1
  local -n result=$2
  local tool

  if has fd; then
    tool=fd
  elif has fdfind; then
    tool=fdfind
  else
    tool=find
  fi

  case "$tool" in
    fd | fdfind)
      mapfile -t result < <("$tool" -H -t f -g "$pattern" 2>/dev/null)
      ;;
    find)
      mapfile -t result < <(find . -type f -name "$pattern" 2>/dev/null)
      ;;
  esac
}

# NUL-safe finder using fd/fdf/find
find0() {
  local root="$1"
  shift
  if has fdf; then
    fdf -H -0 "$@" . "$root"
  elif has fd; then
    fd -H -0 "$@" . "$root"
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

# Get package manager name only (without options)
get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then
    detect_pkg_manager >/dev/null
  fi
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

#============ SQLite Maintenance ============
# Vacuum a single SQLite database and return bytes saved
vacuum_sqlite() {
  local db=$1 s_old s_new
  [[ -f $db ]] || {
    printf '0\n'
    return
  }
  # Skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && {
    printf '0\n'
    return
  }
  # Validate it's actually a SQLite database file
  # Use fixed-string grep (-F) for faster literal matching
  if ! head -c 16 "$db" 2>/dev/null | grep -qF -- 'SQLite format 3'; then
    printf '0\n'
    return
  fi
  s_old=$(stat -c%s "$db" 2>/dev/null) || {
    printf '0\n'
    return
  }
  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || {
    printf '0\n'
    return
  }
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
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 1 -type f)
  ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}

#============ Process Management ============
# Wait for processes to exit, kill if timeout
ensure_not_running() {
  local proc=$1 timeout=${2:-6}
  pgrep -x -u "$USER" "$proc" &>/dev/null || return 0
  warn "Waiting for ${proc} to exit..."
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" "$proc" &>/dev/null || return 0
    sleep 1
  done
  warn "Killing ${proc}..."
  pkill -KILL -x -u "$USER" "$proc" &>/dev/null || :
  sleep 1
}

# Wait for multiple processes to exit, kill if timeout
ensure_not_running_any() {
  local timeout=6 p
  # Optimized: Use single pgrep with pattern instead of multiple calls
  local pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}

  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return

  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && warn "Waiting for ${p} to exit..."
  done

  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
    sleep 1
  done

  # Kill any remaining processes (single pkill call)
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    warn "Killing remaining processes..."
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
    sleep 1
  fi
}

#============ Path Cleaning Helpers ============
# Helper to expand wildcard paths safely
_expand_wildcards() {
  local path=$1
  local -n result_ref="$2"
  if [[ $path == *\** ]]; then
    # Use globbing directly and collect existing items
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a items=("$path")
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
    shopt -u nullglob
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

# Clean paths safely
clean_paths() {
  local -a expanded=()
  for p in "$@"; do
    _expand_wildcards "$p" expanded
  done
  ((${#expanded[@]} > 0)) && rm -rf "${expanded[@]}" 2>/dev/null || :
}

# Clean paths with sudo
clean_with_sudo() {
  local -a expanded=()
  for p in "$@"; do
    _expand_wildcards "$p" expanded
  done
  ((${#expanded[@]} > 0)) && sudo rm -rf "${expanded[@]}" 2>/dev/null || :
}

#============ Download Tool Detection ============
# Get best available download tool (with optional skip for piping)
# Usage: get_download_tool [--no-aria2]
_DOWNLOAD_TOOL_CACHED=""
# shellcheck disable=SC2120
get_download_tool() {
  local skip_aria2=0
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
  # Return cached if available and aria2 not being skipped
  if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then
    printf '%s' "$_DOWNLOAD_TOOL_CACHED"
    return 0
  fi
  local tool
  if [[ $skip_aria2 -eq 0 ]] && has aria2c; then
    tool=aria2c
  elif has curl; then
    tool=curl
  elif has wget2; then
    tool=wget2
  elif has wget; then
    tool=wget
  else
    return 1
  fi
  [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED=$tool
  printf '%s' "$tool"
}

# Download a file using best available tool
# Usage: download_file <url> <output_path>
download_file() {
  local url=$1 output=$2 tool
  # shellcheck disable=SC2119
  tool=$(get_download_tool) || return 1
  case $tool in
    aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "${output%/*}" -o "${output##*/}" "$url" ;;
    curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;;
    wget2) wget2 -q -O "$output" "$url" ;;
    wget) wget -qO "$output" "$url" ;;
    *) return 1 ;;
  esac
}

#============ Privilege Escalation Detection ============
# Detect best privilege escalation tool
PRIV_CMD=""
if has sudo-rs; then
  PRIV_CMD=sudo-rs
elif has sudo; then
  PRIV_CMD=sudo
elif has doas; then
  PRIV_CMD=doas
fi
export PRIV_CMD

#============ Distribution Detection ============
is_arch() { has pacman; }
is_debian() { has apt; }
is_pi() { [[ $(uname -m) =~ ^(arm|aarch64) ]]; }
is_wayland() { [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; }
