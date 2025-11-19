#!/usr/bin/env bash
# Common library for Linux-OS bash scripts
# Provides shared functions, color definitions, and utilities
# Source this file in your scripts: source "${BASH_SOURCE%/*}/lib/common.sh" || exit 1

set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
LC_ALL=C LANG=C LANGUAGE=C

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
has(){ command -v "$1" &>/dev/null; }

# Echo with formatting support
xecho(){ printf '%b\n' "$*"; }
# Logging functions
log(){ xecho "$*"; }
die(){ xecho "${RED}Error:${DEF} $*" >&2; exit 1; }

# Confirmation prompt
confirm(){ printf '%s [y/N]: ' "$1" >&2; read -r ans; [[ $ans == [Yy]* ]]; }

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner(){
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do
    lines+=("$line")
  done <<<"$banner"
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
get_update_banner(){
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}
get_clean_banner(){
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
print_named_banner(){
  local name="$1" title="${2:-Meow (> ^ <)}" banner
  case "$name" in
  update) banner=$(get_update_banner) ;;
  clean) banner=$(get_clean_banner) ;;
  *) die "Unknown banner name: $name" ;;
  esac
  print_banner "$banner" "$title"
}

#============ System Maintenance Functions ============
# Run system maintenance commands safely
run_system_maintenance(){
  local cmd=$1; shift; local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in
    modprobed-db) "$cmd" store &>/dev/null || :;;
    hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &>/dev/null || :;;
    mandb) sudo "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :;;
    *) sudo "$cmd" "${args[@]}" &>/dev/null || :;;
  esac
}

#============ Disk Usage Helpers ============
# Capture current disk usage
capture_disk_usage(){
  local var_name=$1; local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

#============ File Finding Helpers ============
# Use fd if available, fallback to find
find_files(){
  if has fd; then
    fd -tf "$@"
  else
    find --type file "$@"
  fi
}

# NUL-safe finder using fd/fdf/find
find0(){
  local root="$1"; shift
  if has fd; then
    fd -tf -0 "$@" . "$root"
  else
    find --type file "$root" "$@" -print0
  fi
}

#============ Package Manager Detection ============
# Detect and return best available AUR helper or pacman
# Cache result to avoid repeated checks
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager(){
  # Return cached result if available
  if [[ -n $_PKG_MGR_CACHED ]]; then
    printf '%s\n' "$_PKG_MGR_CACHED"
    printf '%s\n' "${_AUR_OPTS_CACHED[@]}"; return 0    
  fi
  local pkgmgr
  if has paru; then
    pkgmgr=paru
    _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc)
  else
    pkgmgr=pacman
    _AUR_OPTS_CACHED=()
  fi
  _PKG_MGR_CACHED=$pkgmgr
  printf '%s\n' "$pkgmgr"
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}
# Get package manager name only (without options)
get_pkg_manager(){
  [[ -z $_PKG_MGR_CACHED ]] && detect_pkg_manager >/dev/null
  printf '%s\n' "$_PKG_MGR_CACHED"
}

# Get AUR options for the detected package manager
get_aur_opts(){
  [[ -z $_PKG_MGR_CACHED ]] && detect_pkg_manager >/dev/null
  printf '%s\n' "${_AUR_OPTS_CACHED[@]}"
}

#============ SQLite Maintenance ============
# Vacuum a single SQLite database and return bytes saved
vacuum_sqlite(){
  local db=$1 s_old s_new
  [[ -f $db ]] || { printf '0\n'; return; }
  # Skip if probably open
  [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0\n'; return; }
  # Validate it's actually a SQLite database file
  if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then
    printf '0\n'; return
  fi
  s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0\n'; return; }
  # VACUUM already rebuilds indices, making REINDEX redundant
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || { printf '0\n'; return; }
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d\n' "$((s_old - s_new))"
}
# Clean SQLite databases in current working directory
clean_sqlite_dbs(){
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
ensure_not_running_any(){
  local timeout=6 p
  # Optimized: Use single pgrep with pattern instead of multiple calls
  local pattern=$(printf '%s|' "$@"); pattern=${pattern%|}
  # Quick check if any processes are running
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
  # Show waiting message for found processes
  for p in "$@"; do
    pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"
  done
  # Single wait loop checking all processes with one pgrep call
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return; sleep 1
  done
  # Kill any remaining processes (single pkill call)
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    printf '  %s\n' "${RED}Killing remaining processes...${DEF}"
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :; sleep 1
  fi
}

#============ Browser Profile Detection ============
# Firefox-family profile discovery
foxdir(){
  local base=$1 p
  [[ -d $base ]] || return 1
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi
  if [[ -f $base/profiles.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini")
    [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }
  fi; return 1
}

# List all Mozilla profiles in a base directory
mozilla_profiles(){
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
chrome_roots_for(){
  case "$1" in
    chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;;
    chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;;
    brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;;
    opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;;
    *) : ;;
  esac
}
# List Default + Profile * dirs under a Chromium root
chrome_profiles(){
  local root="$1" d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done
}

#============ Path Cleaning Helpers ============
# Helper to expand wildcard paths safely
_expand_wildcards(){
  local path="$1"; local -n result_ref=$2
  if [[ $path == *\** ]]; then
    # shellcheck disable=SC2206
    local -a items=($path)
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

# Clean arrays of file/directory paths
clean_paths(){
  local paths=("$@") path
  # Batch check existence to reduce syscalls
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  # Batch delete all existing paths at once
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root "${existing_paths[@]}" &>/dev/null || :
}
# Clean paths with privilege escalation
clean_with_sudo(){
  local paths=("$@") path
  # Batch check existence to reduce syscalls and sudo invocations
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  # Batch delete all existing paths at once with single sudo call
  [[ ${#existing_paths[@]} -gt 0 ]] && sudo rm -rf --preserve-root "${existing_paths[@]}" &>/dev/null || :
}

#============ Download Tool Detection ============
# Get best available download tool (with optional skip for piping)
# Usage: get_download_tool [--no-aria2]
# shellcheck disable=SC2120
_DOWNLOAD_TOOL_CACHED=""
get_download_tool(){
  local skip_aria2=0 tool
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
  # Return cached if available and aria2 not being skipped
  if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then
    printf '%s' "$_DOWNLOAD_TOOL_CACHED"; return 0
  fi
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
  [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED="$tool"; printf '%s' "$tool"
}
# Download a file using best available tool
# Usage: download_file <url> <output_path>
download_file(){
  local url=$1 output=$2 tool
  # shellcheck disable=SC2119
  tool=$(get_download_tool) || return 1
  case $tool in
    aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "$(dirname "$output")" -o "$(basename "$output")" "$url" ;;
    curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;;
    wget2) wget2 -qO "$output" "$url" ;;
    wget) wget -qO "$output" "$url" ;;
    *) return 1 ;;
  esac
}
return 0
