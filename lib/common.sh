#!/usr/bin/env bash
# Common helper functions and utilities for Linux-OS scripts
# Source this file in your scripts: source "${BASH_SOURCE%/*}/../lib/common.sh"

# Prevent multiple sourcing
[[ -n ${LINUX_OS_COMMON_LOADED:-} ]] && return 0
readonly LINUX_OS_COMMON_LOADED=1

# ============================================================================
# SHELL INITIALIZATION
# ============================================================================

# Initialize shell with strict error handling and sane defaults
init_shell() {
  set -Eeuo pipefail
  shopt -s nullglob globstar extglob dotglob 2>/dev/null || :
  IFS=$'\n\t'
  export LC_ALL=C LANG=C
}

# ============================================================================
# COLOR DEFINITIONS (Trans Flag Palette + Standard ANSI)
# ============================================================================

# Standard ANSI colors
readonly BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
readonly BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'

# Trans flag palette
readonly LBLU=$'\e[38;5;117m' # Light blue
readonly PNK=$'\e[38;5;218m'  # Pink
readonly BWHT=$'\e[97m'       # Bright white

# Formatting
readonly DEF=$'\e[0m' # Reset
readonly BLD=$'\e[1m' # Bold
readonly DIM=$'\e[2m' # Dim
readonly UL=$'\e[4m'  # Underline

# Export for subshells if needed
export BLK RED GRN YLW BLU MGN CYN WHT LBLU PNK BWHT DEF BLD DIM UL

# ============================================================================
# CORE UTILITY FUNCTIONS
# ============================================================================

# Check if command exists in PATH
# Usage: has command_name
has() { command -v "$1" &>/dev/null; }

# Printf wrapper for consistent output formatting
# Usage: xecho "formatted text"
xecho() { printf '%b\n' "$*"; }

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Standard log message with blue arrow prefix
# Usage: log "message"
log() { xecho "${BLU}→${DEF} $*"; }

# Warning message with yellow prefix
# Usage: warn "warning message"
warn() { xecho "${YLW}⚠${DEF} $*" >&2; }

# Error message with red prefix to stderr
# Usage: err "error message"
err() { xecho "${RED}✗${DEF} $*" >&2; }

# Fatal error - print message and exit with code
# Usage: die "error message" [exit_code]
die() {
  err "$1"
  exit "${2:-1}"
}

# Debug logging (only when DEBUG=1)
# Usage: dbg "debug message"
dbg() {
  [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :
}

# Success message with green checkmark
# Usage: ok "success message"
ok() { xecho "${GRN}✓${DEF} $*"; }

# Info message with cyan prefix
# Usage: info "info message"
info() { xecho "${CYN}ℹ${DEF} $*"; }

# ============================================================================
# USER INTERACTION
# ============================================================================

# Confirm action with user (returns 0 for yes, 1 for no)
# Usage: confirm "Proceed with operation?" && do_something
confirm() {
  local prompt="${1:-Continue?}"
  local reply
  printf '%b' "${YLW}?${DEF} ${prompt} [y/N] "
  read -r reply
  [[ $reply =~ ^[Yy]$ ]]
}

# ============================================================================
# ERROR HANDLING HELPERS
# ============================================================================

# Error handler for ERR trap - shows line number
# Usage: trap 'on_err $LINENO' ERR
on_err() {
  err "Failed at line ${1:-?}"
}

# Standard cleanup function template (override in your script)
# Usage: cleanup(){ your_cleanup_code; }; trap cleanup EXIT
cleanup() {
  set +e
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}

# Setup standard traps for error handling
# Usage: setup_traps
setup_traps() {
  trap 'cleanup' EXIT
  trap 'on_err $LINENO' ERR
  trap ':' INT TERM
}

# ============================================================================
# SUDO/PRIVILEGE DETECTION
# ============================================================================

# Detect and cache privilege escalation command
# Sets PRIV_CMD global variable
# Usage: detect_priv_cmd
detect_priv_cmd() {
  if [[ -n ${PRIV_CMD:-} ]]; then
    return 0
  fi

  if [[ $EUID -eq 0 ]]; then
    PRIV_CMD=""
  elif has sudo-rs; then
    PRIV_CMD="sudo-rs"
  elif has sudo; then
    PRIV_CMD="sudo"
  elif has doas; then
    PRIV_CMD="doas"
  else
    die "No privilege escalation command found (sudo/sudo-rs/doas)"
  fi

  export PRIV_CMD
}

# Run command with privilege escalation
# Usage: run_priv command args...
run_priv() {
  detect_priv_cmd
  if [[ -z $PRIV_CMD ]]; then
    "$@"
  else
    "$PRIV_CMD" "$@"
  fi
}

# ============================================================================
# TOOL DETECTION WITH FALLBACKS
# ============================================================================

# Find command with fallback chain: fd → fdfind → find
# Sets FD_CMD global variable
detect_fd() {
  if [[ -n ${FD_CMD:-} ]]; then
    return 0
  fi

  if has fd; then
    FD_CMD="fd"
  elif has fdfind; then
    FD_CMD="fdfind"
  elif has find; then
    FD_CMD="find"
  else
    die "No find command available"
  fi

  export FD_CMD
}

# Grep command with fallback: rg → grep
# Sets GREP_CMD global variable
detect_grep() {
  if [[ -n ${GREP_CMD:-} ]]; then
    return 0
  fi

  if has rg; then
    GREP_CMD="rg"
  elif has grep; then
    GREP_CMD="grep -E"
  else
    die "No grep command available"
  fi

  export GREP_CMD
}

# Download command with fallback: aria2c → curl → wget2 → wget
# Sets DL_CMD and DL_ARGS global variables
detect_download() {
  if [[ -n ${DL_CMD:-} ]]; then
    return 0
  fi

  if has aria2c; then
    DL_CMD="aria2c"
    DL_ARGS=(-x 16 -s 16 -k 1M --file-allocation=none)
  elif has curl; then
    DL_CMD="curl"
    DL_ARGS=(-fsSL --proto '=https' --tlsv1.3)
  elif has wget2; then
    DL_CMD="wget2"
    DL_ARGS=(-q -O-)
  elif has wget; then
    DL_CMD="wget"
    DL_ARGS=(-q -O-)
  else
    die "No download command available"
  fi

  export DL_CMD DL_ARGS
}

# JSON processor with fallback: jaq → jq
# Sets JSON_CMD global variable
detect_json() {
  if [[ -n ${JSON_CMD:-} ]]; then
    return 0
  fi

  if has jaq; then
    JSON_CMD="jaq"
  elif has jq; then
    JSON_CMD="jq"
  else
    die "No JSON processor available (jaq/jq)"
  fi

  export JSON_CMD
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

# NUL-safe file finder with fallback to find
# Usage: find0 pattern [path]
find0() {
  local pattern=${1:?}
  local path=${2:-.}

  detect_fd

  if [[ $FD_CMD == "fd" ]] || [[ $FD_CMD == "fdfind" ]]; then
    "$FD_CMD" -H -0 "$pattern" "$path"
  else
    find "$path" -name "$pattern" -print0
  fi
}

# Download file with automatic tool selection
# Usage: download_file url [output_file]
download_file() {
  local url=${1:?}
  local output=${2:-}

  detect_download

  case $DL_CMD in
    aria2c)
      if [[ -n $output ]]; then
        aria2c "${DL_ARGS[@]}" -o "$output" "$url"
      else
        aria2c "${DL_ARGS[@]}" -o- "$url"
      fi
      ;;
    curl)
      if [[ -n $output ]]; then
        curl "${DL_ARGS[@]}" -o "$output" "$url"
      else
        curl "${DL_ARGS[@]}" "$url"
      fi
      ;;
    wget* | wget2)
      if [[ -n $output ]]; then
        "$DL_CMD" "${DL_ARGS[@]}" -O "$output" "$url"
      else
        "$DL_CMD" "${DL_ARGS[@]}" "$url"
      fi
      ;;
  esac
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================

# Check if running on Wayland
is_wayland() {
  [[ ${XDG_SESSION_TYPE:-} == wayland ]] || [[ -n ${WAYLAND_DISPLAY:-} ]]
}

# Check if running on Arch-based system
is_arch() {
  has pacman
}

# Check if running on Debian-based system
is_debian() {
  has apt
}

# Check if running on Raspberry Pi (ARM architecture)
is_pi() {
  [[ $(uname -m) =~ ^(arm|aarch64) ]]
}

# Detect current distribution
# Returns: arch, debian, or unknown
detect_distro() {
  if is_arch; then
    printf 'arch'
  elif is_debian; then
    printf 'debian'
  else
    printf 'unknown'
  fi
}

# ============================================================================
# ARRAY UTILITIES
# ============================================================================

# Load array from file, filtering comments and blank lines
# Usage: load_array_from_file arrayname filename
load_array_from_file() {
  local -n arr="$1"
  local file=${2:?}

  [[ -f $file ]] || die "File not found: $file"

  mapfile -t arr < <(grep -v '^\s*#' "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
}

# ============================================================================
# PROCESS UTILITIES
# ============================================================================

# Wait for process to exit with timeout
# Usage: wait_for_process process_name timeout_seconds
wait_for_process() {
  local proc=${1:?}
  local timeout=${2:-30}
  local elapsed=0

  while pgrep -x "$proc" &>/dev/null; do
    sleep 1
    ((elapsed++))
    if ((elapsed >= timeout)); then
      return 1
    fi
  done

  return 0
}

# Kill process by name if running
# Usage: kill_process process_name
kill_process() {
  local proc=${1:?}

  if pgrep -x "$proc" &>/dev/null; then
    pkill -TERM "$proc" 2>/dev/null || :
    sleep 2
    if pgrep -x "$proc" &>/dev/null; then
      pkill -KILL "$proc" 2>/dev/null || :
    fi
  fi
}

# ============================================================================
# RETURN SUCCESS
# ============================================================================

return 0
