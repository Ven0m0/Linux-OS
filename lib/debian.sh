#!/usr/bin/env bash
# lib/debian.sh - Debian/Raspberry Pi shared library
# Provides: DietPi functions, APT helpers, Debian-specific utilities
# Requires: lib/core.sh
# shellcheck disable=SC2034
[[ -n ${_LIB_DEBIAN_LOADED:-} ]] && return 0
_LIB_DEBIAN_LOADED=1

# Source core library if not loaded
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=lib/core.sh
[[ -z ${_LIB_CORE_LOADED:-} ]] && source "${SCRIPT_DIR}/core.sh"

# Common Debian environment
export DEBIAN_FRONTEND=noninteractive

#============ DietPi Functions ============
# Load DietPi globals if available
load_dietpi_globals(){
  [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
}

# Run DietPi cleanup commands if available
run_dietpi_cleanup(){
  if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
    if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then
      warn "dietpi-update failed (both standard and fallback commands)."
    fi
    sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
    sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
  fi
}

#============ APT Functions ============
# Clean APT package manager cache
clean_apt_cache(){
  sudo apt-get clean -y 2>/dev/null || :
  sudo apt-get autoclean -y 2>/dev/null || :
  sudo apt-get autoremove --purge -y 2>/dev/null || :
}

# Run apt-get with common options
run_apt(){
  sudo apt-get -y --allow-releaseinfo-change \
    -o Acquire::Languages=none \
    -o APT::Get::Fix-Missing=true \
    -o APT::Get::Fix-Broken=true \
    "$@"
}

# Update system using best available package manager
update_apt_system(){
  sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || :
  if has apt-fast; then
    sudo apt-fast update -y --allow-releaseinfo-change
    sudo apt-fast upgrade -y --no-install-recommends
    sudo apt-fast dist-upgrade -y --no-install-recommends
    clean_apt_cache
    sudo apt-fast autopurge -yq 2>/dev/null || :
  elif has nala; then
    sudo nala upgrade --no-install-recommends
    sudo nala clean
    sudo nala autoremove
    sudo nala autopurge
  else
    run_apt update
    run_apt dist-upgrade
    run_apt full-upgrade
    clean_apt_cache
  fi
  sudo dpkg --configure -a >/dev/null
}

#============ System Cleanup Functions ============
# Clean system cache directories
clean_cache_dirs(){
  sudo rm -rf /tmp/* 2>/dev/null || :
  sudo rm -rf /var/tmp/* 2>/dev/null || :
  sudo rm -rf /var/cache/apt/archives/* 2>/dev/null || :
  rm -rf ~/.cache/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
  rm -rf ~/.thumbnails/* 2>/dev/null || :
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || :
}

# Empty trash directories
clean_trash(){
  rm -rf ~/.local/share/Trash/* 2>/dev/null || :
  sudo rm -rf /root/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/snap/*/*/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/.var/app/*/data/Trash/* 2>/dev/null || :
}

# Clean crash dumps and core dumps
clean_crash_dumps(){
  if has coredumpctl; then
    sudo coredumpctl --quiet --no-legend clean 2>/dev/null || :
  fi
  sudo rm -rf /var/crash/* 2>/dev/null || :
  sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null || :
}

# Clean shell and Python history files
clean_history_files(){
  rm -f ~/.python_history 2>/dev/null || :
  sudo rm -f /root/.python_history 2>/dev/null || :
  rm -f ~/.bash_history 2>/dev/null || :
  sudo rm -f /root/.bash_history 2>/dev/null || :
  history -c 2>/dev/null || :
}

# Clean systemd journal logs
clean_journal_logs(){
  sudo journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
  sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
  sudo systemd-tmpfiles --clean 2>/dev/null || :
}

#============ Init/Working Directory Helpers ============
# Initialize working directory
init_workdir(){
  local workdir
  workdir="$(cd "${BASH_SOURCE[1]%/*}" && pwd)" || {
    echo "Failed to determine working directory" >&2
    exit 1
  }
  cd "$workdir" || {
    echo "Failed to change to working directory: $workdir" >&2
    exit 1
  }
  printf '%s\n' "$workdir"
}

# Get script directory
get_script_dir(){
  local script="${BASH_SOURCE[1]:-$0}"
  cd "${script%/*}" && pwd
}

#============ Privilege Helpers ============
# Get best available sudo command
get_sudo_cmd(){
  local sudo_cmd
  sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || {
    warn "No valid privilege escalation tool found (sudo-rs, sudo, doas)."
    return 1
  }
  printf '%s\n' "$sudo_cmd"
}

# Initialize sudo (cache credentials)
init_sudo(){
  local sudo_cmd
  sudo_cmd="$(get_sudo_cmd)" || return 1
  if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then
    "$sudo_cmd" -v 2>/dev/null || :
  fi
}

# Check if running as root
check_root(){
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root."
  fi
}

# Require root, re-execute with sudo if needed
require_root(){
  if [[ $EUID -ne 0 ]]; then
    local script_path
    script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}")
    exec sudo "$script_path" "$@"
  fi
}

#============ Find with Fallback ============
# Find files/directories with fd/fdfind/find fallback
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fd; then
    fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  elif has fdfind; then
    fdfind -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
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
