#!/usr/bin/env bash
# Common library for RaspberryPi scripts
# This file contains shared functions and environment setup used across multiple scripts

# Standard environment setup
# When this file is sourced, it sets safe bash options and exports common environment variables.
# Note: Sourcing this file will modify the calling shell's environment (not just child processes).
export LC_ALL=C LANG=C
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
# Check if a command exists in PATH
# Usage: has <command_name>
# Returns: 0 if command exists, 1 otherwise
has() {
  command -v -- "$1" &>/dev/null
}

# Get the name of a command from PATH
# Usage: hasname <command_name>
# Returns: The basename of the command path, or 1 if not found
hasname() {
  local x
  if ! x=$(type -P -- "$1"); then
    return 1
  fi
  printf '%s\n' "${x##*/}"
}

# Alternative command detection function (compatible with different naming conventions)
is_program_installed() {
  command -v "$1" &>/dev/null
}

# Get the directory where the calling script resides
# Usage: WORKDIR=$(get_workdir)
# Note: This uses BASH_SOURCE[1] to get the caller's location, not this library's location
get_workdir() {
  local script="${BASH_SOURCE[1]:-$0}"
  builtin cd -- "$(dirname -- "$script")" && printf '%s\n' "$PWD"
}

# Initialize working directory and change to it
# This is a common pattern where scripts need to run from their own directory
init_workdir() {
  local workdir
  workdir="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[1]:-}")" && printf '%s\n' "$PWD")"
  cd "$workdir" || {
    echo "Failed to change to working directory: $workdir" >&2
    exit 1
  }
}

# Require root privileges to run the script
# If not root, attempts to re-run with sudo
# Usage: require_root "$@"
require_root() {
  if [[ $EUID -ne 0 ]]; then
    local script_path
    script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}")
    sudo "$script_path" "$@" || {
      echo 'Administrator privileges are required.' >&2
      exit 1
    }
    exit 0
  fi
}

# Simple root check without auto-elevation
# Usage: check_root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

# Load DietPi globals if available
# DietPi-specific functionality for systems running DietPi
load_dietpi_globals() {
  [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
}

# Run DietPi cleanup commands if available
run_dietpi_cleanup() {
  if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
    if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then
      echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2
    fi
    sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
    sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
  fi
}

# Setup standard bash environment for scripts
# Sets safe shell options and standardizes IFS
# Usage: setup_environment
setup_environment() {
  set -euo pipefail
  shopt -s nullglob globstar execfail
  IFS=$'\n\t'
}

# Get sudo command available on the system
# Checks for sudo-rs, sudo, or doas in order of preference
# Returns: Command name if found, exits with error if none available
# Usage: SUDO_CMD=$(get_sudo_cmd)
get_sudo_cmd() {
  local sudo_cmd
  sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || {
    echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
    return 1
  }
  printf '%s\n' "$sudo_cmd"
}

# Initialize sudo session if not root
# Validates sudo availability and pre-authenticates
# Usage: init_sudo
init_sudo() {
  local sudo_cmd
  sudo_cmd="$(get_sudo_cmd)" || return 1
  
  if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then
    "$sudo_cmd" -v 2>/dev/null || :
  fi
}

# Find files with fallback to standard find
# Tries fdf, fd, then find in that order
# Usage: find_with_fallback <type> <pattern> <path> [<action>] [<action_args>...]
# Example: find_with_fallback f "*.sh" /path -x chmod 755
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
