#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
# Usage: sqlite-tune db.sqlite [aggressive|safe|readonly]
# ============ Inlined from lib/common.sh ============
export LC_ALL=C LANG=C
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'
	'
has() { command -v -- "$1" &> /dev/null; }
hasname() {
  local x
  if ! x=$(type -P -- "$1"); then return 1; fi
  printf '%s
' "${x##*/}"
}
has() { command -v -- "$1" &> /dev/null; }
wdir() {
  local script="${BASH_SOURCE[1]:-$0}"
  builtin cd -- "${script%/*}" && printf '%s\n' "$PWD"
}
init_wdir() {
  local wdir
  wdir="$(builtin cd -- "${BASH_SOURCE[1]:-$0%/*}" && printf '%s\n
' "$PWD")"
  cd "$wdir" || {
    echo "Failed to change to working directory: $wdir" >&2
    exit 1
  }
}
require_root() { if [[ $EUID -ne 0 ]]; then
  local script_path
  script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}")
  sudo "$script_path" "$@" || {
    echo 'Administrator privileges are required.' >&2
    exit 1
  }
  exit 0
fi; }
check_root() { if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi; }
load_dietpi_globals() { [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &> /dev/null || :; }
run_dietpi_cleanup() { if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
  if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2; fi
  sudo /boot/dietpi/func/dietpi-logclear 2 2> /dev/null || G_SUDO dietpi-logclear 2 2> /dev/null || :
  sudo /boot/dietpi/func/dietpi-cleaner 2 2> /dev/null || G_SUDO dietpi-cleaner 2 2> /dev/null || :
fi; }
get_sudo_cmd() {
  local sudo_cmd
  sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || {
    echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
    return 1
  }
  printf '%s
' "$sudo_cmd"
}
init_sudo() {
  local sudo_cmd
  sudo_cmd="$(get_sudo_cmd)" || return 1
  if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then "$sudo_cmd" -v 2> /dev/null || :; fi
}
find_with_fallback() {
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2> /dev/null || shift $#
  if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; else
    local find_type_arg
    case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac
    if [[ -n $action ]]; then find "$search_path" "$find_type_arg" -name "$pattern" "$action" "$@"; else find "$search_path" "$find_type_arg" -name "$pattern"; fi
  fi
}
die() {
  echo "ERROR: $*" >&2
  exit 1
}
# ============ End of inlined lib/common.sh ============

db=${1:?db path}
mode=${2:-safe}
run() { sqlite3 "$db" "$1"; }

case $mode in
  safe)
    run 'PRAGMA foreign_keys=ON;'
    run 'PRAGMA journal_mode=WAL;'
    run 'PRAGMA synchronous=FULL;'
    run 'PRAGMA wal_autocheckpoint=400;'
    run 'PRAGMA temp_store=MEMORY;'
    run 'PRAGMA mmap_size=67108864;'
    run 'PRAGMA cache_size=-65536;'
    run 'PRAGMA optimize;'
    ;;
  aggressive)
    run 'PRAGMA foreign_keys=ON;'
    run 'PRAGMA journal_mode=WAL;'
    run 'PRAGMA synchronous=NORMAL;'
    run 'PRAGMA wal_autocheckpoint=1000;'
    run 'PRAGMA temp_store=MEMORY;'
    run 'PRAGMA mmap_size=268435456;'
    run 'PRAGMA cache_size=-262144;'
    run 'PRAGMA cache_spill=OFF;'
    run 'PRAGMA optimize;'
    ;;
  readonly)
    # Assumes you open DB with immutable=1 externally if possible
    run 'PRAGMA query_only=ON;'
    run 'PRAGMA mmap_size=268435456;'
    run 'PRAGMA cache_size=-131072;'
    ;;
  *) die "unknown mode $mode" ;;
esac
