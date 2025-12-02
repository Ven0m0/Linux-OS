#!/usr/bin/env bash
# lib/core.sh - Core shared library for shell scripts
# Provides: shell settings, colors, logging, and common helper functions
# shellcheck disable=SC2034
[[ -n ${_LIB_CORE_LOADED:-} ]] && return 0
_LIB_CORE_LOADED=1

#============ Shell Settings ============
set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"

#============ Colors (Trans flag palette) ============
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
export BLK RED GRN YLW BLU MGN CYN WHT LBLU PNK BWHT DEF BLD

#============ Core Helper Functions ============
# Check if command exists
has(){ command -v -- "$1" &>/dev/null; }

# Get command path name
hasname(){
  local x
  x=$(type -P -- "$1" 2>/dev/null) || return 1
  printf '%s\n' "${x##*/}"
}

# Echo with formatting support
xecho(){ printf '%b\n' "$*"; }

# Logging functions
log(){ xecho "$*"; }
msg(){ printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
warn(){ printf '%b%s%b\n' "$YLW" "$*" "$DEF" >&2; }
err(){ printf '%b%s%b\n' "$RED" "$*" "$DEF" >&2; }
die(){
  err "${1:-Error}"
  exit "${2:-1}"
}

# Debug logging (enabled by DEBUG=1)
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && xecho "[DBG] $*" || :; }

# Confirmation prompt
confirm(){
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

#============ Banner Printing Functions ============
# Print banner with trans flag gradient
# Usage: print_banner "banner_text" [title]
print_banner(){
  local banner="$1" title="${2:-}"
  local -a flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
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

#============ File Finding Helpers ============
# Use fd if available, fallback to find
find_files(){
  if has fd; then
    fd -H "$@"
  elif has fdfind; then
    fdfind -H "$@"
  else
    find "$@"
  fi
}

# NUL-safe finder using fd/fdfind/find
find0(){
  local root="$1"
  shift
  if has fd; then
    fd -H -0 "$@" . "$root"
  elif has fdfind; then
    fdfind -H -0 "$@" . "$root"
  else
    find "$root" "$@" -print0
  fi
}

#============ Path Cleaning Helpers ============
# Helper to expand wildcard paths safely
_expand_wildcards(){
  local path=$1
  local -n result_ref="$2"
  if [[ $path == *\** ]]; then
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a items=($path)
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

# Clean paths (user files)
clean_paths(){
  local paths=("$@") path
  local -a existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

# Clean paths with sudo (system files)
clean_with_sudo(){
  local paths=("$@") path
  local -a existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && sudo rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

#============ Download Tool Detection ============
_DOWNLOAD_TOOL_CACHED=""
# shellcheck disable=SC2120
get_download_tool(){
  local skip_aria2=0
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
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
download_file(){
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

#============ Disk Usage Helpers ============
# Capture current disk usage
capture_disk_usage(){
  df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'
}
