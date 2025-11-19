#!/usr/bin/env bash
# Linux-OS Base Library
# Core functions and utilities shared across all scripts
# Source this file: source "${BASH_SOURCE%/*}/lib/base.sh" || exit 1
#
# This library provides:
# - Environment setup (locale, shell options)
# - Color constants
# - Core helper functions (has, log, die, etc.)
# - Privilege escalation utilities
# - Working directory management
# - File finding utilities
# - Download tool detection

# ============================================================================
# Environment Setup
# ============================================================================
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'

# Export common locale settings
export LC_ALL=C LANG=C LANGUAGE=C

# ============================================================================
# Color Constants (Trans Flag Palette)
# ============================================================================
# Standard colors
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Export so they're available to sourcing scripts
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD

# ============================================================================
# Core Helper Functions
# ============================================================================

# Check if command exists in PATH
# Usage: has <command_name>
# Returns: 0 if command exists, 1 otherwise
has() {
  command -v "$1" &>/dev/null
}

# Get the basename of a command from PATH
# Usage: hasname <command_name>
# Returns: The basename of the command path, or 1 if not found
hasname() {
  local cmd_path
  if ! cmd_path=$(command -v "$1" 2>/dev/null); then
    return 1
  fi
  printf '%s\n' "${cmd_path##*/}"
}

# Alternative command detection (for compatibility)
# Usage: is_program_installed <program>
is_program_installed() {
  command -v "$1" &>/dev/null
}

# ============================================================================
# Logging Functions
# ============================================================================

# Echo with formatting support
# Usage: xecho "formatted text"
xecho() {
  printf '%b\n' "$*"
}

# Generic logging
# Usage: log "message"
log() {
  xecho "$*"
}

# Informational message (blue)
# Usage: info "information"
info() {
  xecho "${BLU}ℹ${DEF} $*"
}

# Success message (green)
# Usage: ok "success message"
ok() {
  xecho "${GRN}✓${DEF} $*"
}

# Warning message (yellow)
# Usage: warn "warning message"
warn() {
  xecho "${YLW}⚠${DEF} $*" >&2
}

# Error message (red, no exit)
# Usage: err "error message"
err() {
  xecho "${RED}✗${DEF} $*" >&2
}

# Fatal error (red, exits)
# Usage: die "fatal error message"
die() {
  xecho "${RED}Error:${DEF} $*" >&2
  exit 1
}

# Section header for structured output
# Usage: section "Section Title"
section() {
  printf '\n%s%s=== %s ===%s\n\n' "$CYN" "$BLD" "$*" "$DEF"
}

# ============================================================================
# Confirmation & Input
# ============================================================================

# Confirmation prompt
# Usage: confirm "Do you want to continue?" && do_something
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}

# ============================================================================
# Privilege Escalation
# ============================================================================

# Detect available privilege escalation tool
# Checks for: sudo-rs, sudo, doas
# Returns: Command name if found, exits if none available and not root
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

# Initialize privilege tool and cache sudo timestamp
# Usage: PRIV_CMD=$(init_priv)
init_priv() {
  local priv_cmd
  priv_cmd=$(get_priv_cmd)
  # Pre-authenticate sudo if needed
  if [[ -n $priv_cmd && $EUID -ne 0 && $priv_cmd =~ ^(sudo-rs|sudo)$ ]]; then
    "$priv_cmd" -v
  fi
  printf '%s' "$priv_cmd"
}

# Run command with privilege escalation if needed
# Usage: run_priv command [args...]
run_priv() {
  local priv_cmd="${PRIV_CMD:-}"
  [[ -z $priv_cmd ]] && priv_cmd=$(get_priv_cmd)

  if [[ $EUID -eq 0 || -z $priv_cmd ]]; then
    "$@"
  else
    "$priv_cmd" -- "$@"
  fi
}

# Require root privileges (exits if not root)
# Usage: require_root
require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root"
  fi
}

# Check if running as root
# Usage: check_root && do_something
check_root() {
  [[ $EUID -eq 0 ]]
}

# ============================================================================
# Working Directory Management
# ============================================================================

# Get the directory where the calling script resides
# Usage: WORKDIR=$(get_workdir)
# Note: Uses BASH_SOURCE[1] to get caller's location
get_workdir() {
  local script="${BASH_SOURCE[1]:-$0}"
  builtin cd -- "$(dirname -- "$script")" && printf '%s\n' "$PWD"
}

# Initialize working directory and change to it
# Usage: init_workdir
init_workdir() {
  local workdir
  workdir="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && printf '%s\n' "$PWD")"
  cd "$workdir" || die "Failed to change to working directory: $workdir"
}

# Get script directory (alternative pattern)
# Usage: SCRIPT_DIR=$(get_script_dir)
get_script_dir() {
  builtin cd -- "$(dirname -- "${BASH_SOURCE[1]:-$0}")" && printf '%s\n' "$PWD"
}

# ============================================================================
# File Finding Utilities
# ============================================================================

# Use fd if available, fallback to find
# Usage: find_files [fd/find args...]
find_files() {
  if has fd; then
    fd -H "$@"
  else
    find "$@"
  fi
}

# NUL-safe finder using fd/fdf/find
# Usage: find0 <root_path> [args...]
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

# Find files with fallback support
# Usage: find_with_fallback <type> <pattern> <path> [action] [action_args...]
find_with_fallback() {
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#

  if has fdf; then
    fdf -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  elif has fd; then
    fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  else
    local find_type_arg
    case "$ftype" in
      f) find_type_arg="-type f" ;;
      d) find_type_arg="-type d" ;;
      l) find_type_arg="-type l" ;;
      *) find_type_arg="-type f" ;;
    esac

    if [[ -n $action ]]; then
      find "$search_path" $find_type_arg -name "$pattern" "$action" "$@"
    else
      find "$search_path" $find_type_arg -name "$pattern"
    fi
  fi
}

# ============================================================================
# Download Tool Detection
# ============================================================================

# Cache for download tool
_DOWNLOAD_TOOL_CACHED=""

# Get best available download tool
# Usage: get_download_tool [--no-aria2]
# Returns: Tool name (aria2c, curl, wget2, wget)
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
  tool=$(get_download_tool) || die "No download tool available (aria2c/curl/wget)"

  case $tool in
    aria2c)
      aria2c -q --max-tries=3 --retry-wait=1 \
        -d "$(dirname "$output")" -o "$(basename "$output")" "$url"
      ;;
    curl)
      curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output"
      ;;
    wget2)
      wget2 -q -O "$output" "$url"
      ;;
    wget)
      wget -qO "$output" "$url"
      ;;
    *)
      return 1
      ;;
  esac
}

# ============================================================================
# Path Manipulation Utilities
# ============================================================================

# Pure bash basename
# Usage: bname "/path/to/file.txt" -> "file.txt"
bname() {
  local path="${1%/}"
  printf '%s\n' "${path##*/}"
}

# Pure bash dirname
# Usage: dname "/path/to/file.txt" -> "/path/to"
dname() {
  local path="${1%/}"
  path="${path%/*}"
  [[ -z $path ]] && path="."
  printf '%s\n' "$path"
}

# ============================================================================
# System Information
# ============================================================================

# Get number of CPU cores
# Usage: nproc_count=$(get_nproc)
get_nproc() {
  nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4
}

# Get current disk usage
# Usage: disk_usage=$(get_disk_usage)
get_disk_usage() {
  df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'
}

# Capture disk usage to a variable
# Usage: capture_disk_usage var_name
capture_disk_usage() {
  local var_name=$1
  local -n ref="$var_name"
  ref=$(get_disk_usage)
}

# ============================================================================
# Cleanup & Validation
# ============================================================================

# Helper to expand wildcard paths safely
# Usage: _expand_wildcards "path/with/*" result_array
_expand_wildcards() {
  local path=$1
  local -n result_ref=$2

  if [[ $path == *\** ]]; then
    # Use globbing directly and collect existing items
    shopt -s nullglob
    # shellcheck disable=SC2206  # Intentional globbing for wildcard expansion
    local -a items=($path)
    for item in "${items[@]}"; do
      [[ -e $item ]] && result_ref+=("$item")
    done
    shopt -u nullglob
  else
    [[ -e $path ]] && result_ref+=("$path")
  fi
}

# Clean arrays of file/directory paths
# Usage: clean_paths "path1" "path2" ...
clean_paths() {
  local paths=("$@") path
  local existing_paths=()

  for path in "${paths[@]}"; do
    _expand_wildcards "$path" existing_paths
  done

  [[ ${#existing_paths[@]} -gt 0 ]] && \
    rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

# Clean paths with privilege escalation
# Usage: clean_with_sudo "path1" "path2" ...
clean_with_sudo() {
  local paths=("$@") path
  local existing_paths=()

  for path in "${paths[@]}"; do
    _expand_wildcards "$path" existing_paths
  done

  [[ ${#existing_paths[@]} -gt 0 ]] && \
    run_priv rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}

# ============================================================================
# Trap & Cleanup Helpers
# ============================================================================

# Setup standard trap handlers
# Usage: setup_traps [cleanup_function]
setup_traps() {
  local cleanup_fn="${1:-cleanup}"
  trap "$cleanup_fn" EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# ============================================================================
# Library Load Confirmation
# ============================================================================

# Mark library as loaded
_BASE_LIB_LOADED=1
return 0
