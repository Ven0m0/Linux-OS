#!/usr/bin/env bash
# Optimized: 2025-11-22 - Applied bash optimization techniques
# Source shared libraries
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# ============ Inlined from lib/common.sh ============
export LC_ALL=C LANG=C
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
has(){ command -v -- "$1" &>/dev/null>/dev/null; }
hasname(){
  local x
  if ! x=$(type -P -- "$1"); then return 1; fi
  printf '%s\n' "${x##*/}"
}
is_program_installed(){ command -v "$1" &>/dev/null>/dev/null; }
get_workdir(){
  local script="${BASH_SOURCE[1]:-$0}"
  builtin cd -- "${script%/*}" && printf '%s\n' "$PWD"
}
init_workdir(){
  local workdir
  workdir="$(builtin cd -- "${BASH_SOURCE[1]:-$0}" && builtin cd -- "${BASH_SOURCE[1]%/*}" && printf '%s\n' "$PWD")"
  cd "$workdir" || {
    echo "Failed to change to working directory: $workdir" >&2
    exit 1
  }
}
require_root(){ if [[ $EUID -ne 0 ]]; then
  local script_path
  script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}")
  sudo "$script_path" "$@" || {
    echo 'Administrator privileges are required.' >&2
    exit 1
  }
  exit 0
fi; }
check_root(){ if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi; }
load_dietpi_globals(){ [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null>/dev/null || :; }
run_dietpi_cleanup(){ if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
  if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2; fi
  sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
  sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
fi; }
setup_environment(){
  set -euo pipefail
  shopt -s nullglob globstar execfail
  IFS=$'\n\t'
}
get_sudo_cmd(){
  local sudo_cmd
  sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || {
    echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
    return 1
  }
  printf '%s\n' "$sudo_cmd"
}
init_sudo(){
  local sudo_cmd
  sudo_cmd="$(get_sudo_cmd)" || return 1
  if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then "$sudo_cmd" -v 2>/dev/null || :; fi
}
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"; else
    local find_type_arg
    case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac
    if [[ -n $action ]]; then find "$search_path" $find_type_arg -name "$pattern" "$action" "$@"; else find "$search_path" $find_type_arg -name "$pattern"; fi
  fi
}
# ============ End of inlined lib/common.sh ============

# Setup environment
setup_environment

sudo apt-get install ntpdate
sudo ntpdate -u ntp.ubuntu.com
sudo apt-get install ca-certificates

# SSH fix - Set proper permissions using find with fallback
if [[ -d ~/.ssh ]]; then
  find_with_fallback f "*" ~/.ssh/ -exec chmod 600 {} +
  find_with_fallback d "*" ~/.ssh/ -exec chmod 700 {} +
  find_with_fallback f "*.pub" ~/.ssh/ -exec chmod 644 {} +
fi

# Fix permissions (700 for directories, 600 for files is more secure than 744)
[[ -d ~/.ssh ]] && sudo chmod 700 ~/.ssh
[[ -d ~/.gnupg ]] && sudo chmod 700 ~/.gnupg

# Nextcloud CasaOS fix
sudo docker exec nextcloud ls -ld /tmp
sudo docker exec nextcloud chown -R www-data:www-data /tmp
sudo docker exec nextcloud chmod -R 755 /tmp
sudo docker exec nextcloud ls -ld /tmp
