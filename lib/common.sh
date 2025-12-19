#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# Common library functions for Linux-OS scripts
# Source this file to use shared utilities and avoid code duplication

# Prevent double-sourcing
[[ -n ${_COMMON_LIB_LOADED:-} ]] && return 0
readonly _COMMON_LIB_LOADED=1

# Color definitions - ANSI escape codes
readonly BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
readonly BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
readonly LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
readonly DEF=$'\e[0m' BLD=$'\e[1m'

# Export colors for use in subshells
export BLK RED GRN YLW BLU MGN CYN WHT LBLU PNK BWHT DEF BLD

# Core utility functions

# Check if command exists
has() {
  command -v -- "$1" &>/dev/null
}

# Echo with formatting support
xecho() {
  printf '%b\n' "$*"
}

# Logging functions with consistent formatting
log() {
  xecho "${GRN}▶${DEF} $*"
}

warn() {
  xecho "${YLW}⚠${DEF} $*" >&2
}

err() {
  xecho "${RED}✗${DEF} $*" >&2
}

# Exit with error message
die() {
  err "$1"
  exit "${2:-1}"
}

# Debug logging (only if DEBUG=1)
dbg() {
  [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :
}

# Confirmation prompt
confirm() {
  local msg="${1:-Continue?}"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

# Find files/directories with fd/fdfind/find fallback
find_with_fallback() {
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}"
  shift 3 2>/dev/null || shift $#
  
  if has fd; then
    fd -H -t "${ftype#-}" "$pattern" "$search_path" "$@"
  elif has fdfind; then
    fdfind -H -t "${ftype#-}" "$pattern" "$search_path" "$@"
  else
    local find_type_arg
    case "${ftype#-}" in
      f) find_type_arg="-type f" ;;
      d) find_type_arg="-type d" ;;
      l) find_type_arg="-type l" ;;
      *) find_type_arg="-type f" ;;
    esac
    find "$search_path" $find_type_arg -name "$pattern" "$@"
  fi
}

# Get user home directory (respects SUDO_USER)
get_user_home() {
  local user="${SUDO_USER:-${USER:-}}"
  [[ -n $user ]] || die "No USER/SUDO_USER detected"
  local home
  home=$(getent passwd "$user" | cut -d: -f6 2>/dev/null || echo "${HOME:-}")
  [[ -n $home && -d $home ]] || die "Cannot resolve home directory for $user"
  printf '%s' "$home"
}

# Write to sysfs/procfs file with sudo if needed
write_sys() {
  local val="$1" path="$2"
  [[ -e $path ]] || return 0
  printf '%s\n' "$val" | sudo tee "$path" >/dev/null
}

# Write same value to multiple sysfs paths
write_sys_many() {
  local val="$1"
  shift
  local path
  for path in "$@"; do
    write_sys "$val" "$path"
  done
}

# Run command with dry-run support
run_cmd() {
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    log "[DRY-RUN] $*"
  else
    "$@"
  fi
}
