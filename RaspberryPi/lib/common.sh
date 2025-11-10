#!/usr/bin/env bash
# Common library for RaspberryPi scripts
# This file contains shared functions and environment setup used across multiple scripts

# Standard environment setup
# Exports common environment variables and sets safe bash options
setup_environment() {
  export LC_ALL=C LANG=C
  export DEBIAN_FRONTEND=noninteractive
  export HOME="/home/${SUDO_USER:-$USER}"
  set -euo pipefail
  shopt -s nullglob globstar execfail
  IFS=$'\n\t'
}

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
    sudo dietpi-update 1 || sudo /boot/dietpi/dietpi-update 1
    sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
    sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
  fi
}
