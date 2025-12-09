#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# Usage: sqlite-tune db.sqlite [aggressive|safe|readonly]
# ============ Inlined from lib/common.sh ============
has(){ command -v -- "$1" &>/dev/null; }
die(){
  echo "ERROR: $*">&2
  exit 1
}
# ============ End of inlined lib/common.sh ============
db=${1:?db path}
mode=${2:-safe}
run(){ sqlite3 "$db" "$1"; }
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
