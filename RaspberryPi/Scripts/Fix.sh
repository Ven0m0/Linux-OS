#!/usr/bin/env bash
# Optimized: 2025-11-22 - Applied bash optimization techniques

set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="${HOME:-/home/${SUDO_USER:-$USER}}"

# Core helper functions
has(){ command -v -- "$1" &>/dev/null; }

# Find files/directories with fdf/fd/fdfind/find fallback
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fdf; then
    fdf -H -t "$ftype" "$pattern" "$search_path" ${action:+"$action"} "$@"
  elif has fd; then
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
