#!/usr/bin/env bash
# Optimized Rank.sh - Pure rate-mirrors implementation
set -euo pipefail; shopt -s nullglob
IFS=$'\n\t'; export LC_ALL=C LANG=C
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"
# Config
MIRRORDIR="/etc/pacman.d"
GPGCONF="$MIRRORDIR/gnupg/gpg.conf"
BACKUPDIR="$MIRRORDIR/.bak"
COUNTRY="${RATE_MIRRORS_ENTRY_COUNTRY:-$(curl -sf https://ipapi.co/country_code || echo DE)}"
ARCH_URL='https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4'
REPOS=(cachyos chaotic-aur endeavouros alhp)
KEYSERVERS=("hkp://keyserver.ubuntu.com" "hkps://keys.openpgp.org" "hkps://pgp.mit.edu" "hkp://keys.gnupg.net")
# Helpers
log(){ printf "\033[1;32m[%s]\033[0m %s\n" "${1:-INFO}" "${*:2}"; }
backup(){
  [[ -f $1 ]] || return 0
  mkdir -p "$BACKUPDIR"
  cp -a "$1" "$BACKUPDIR/${1##*/}-$(date +%s).bak"
  find "$BACKUPDIR" -name "${1##*/}-*.bak" -printf '%T@ %p\n' | sort -rn | tail -n+6 | awk '{print $2}' | xargs -r rm -f
}
# Actions
rank_keys(){
  [[ -f $GPGCONF ]] || return 0
  log KEY "Ranking keyservers..."
  local best="" min=9999
  for u in "${KEYSERVERS[@]}"; do
    local t1; t1=$(date +%s%3N)
    if curl -sIo /dev/null -m2 "${u/hkp/http}"; then
      local diff=$(( $(date +%s%3N) - t1 ))
      (( diff < min )) && { min=$diff; best=$u; }
    fi
  done
  [[ $best ]] && { backup "$GPGCONF"; sed -i "s|^[[:space:]]*keyserver .*|keyserver $best|" "$GPGCONF"; log KEY "Best: $best ($min ms)"; }
}
rank_repo(){
  local name=$1 file="$MIRRORDIR/${1}-mirrorlist"
  [[ -f $file ]] || return 0
  log REPO "Ranking $name..."
  backup "$file"
  local tmp; tmp=$(mktemp)
  # Extract URLs and pipe to rate-mirrors
  grep -oP 'https?://[^ ]+' "$file" | sort -u | rate-mirrors --save="$tmp" --entry-country="$COUNTRY" stdin \
    --fetch-mirrors-timeout=5000 --path-to-return='$repo/os/$arch' &>/dev/null || { rm -f "$tmp"; return 1; }
  install -m644 "$tmp" "$file"; rm -f "$tmp"
}
rank_arch(){
  local file="$MIRRORDIR/mirrorlist"
  log ARCH "Fetching & Ranking Arch..."
  backup "$file"
  local tmp; tmp=$(mktemp)
  rate-mirrors --save="$tmp" --entry-country="$COUNTRY" --top-mirrors-number-to-retest=5 arch --url "$ARCH_URL" &>/dev/null \
    || { rm -f "$tmp"; return 1; }
  install -m644 "$tmp" "$file"; rm -f "$tmp"
}
# Main
log INFO "Country: $COUNTRY | Tool: rate-mirrors"
rank_keys || :
# CachyOS Specific Handling
if command -v cachyos-rate-mirrors &>/dev/null; then
  log CACHY "Using cachyos-rate-mirrors wrapper..."
  cachyos-rate-mirrors
else
  rank_repo "cachyos"
  rank_arch
  for r in "${REPOS[@]}"; do [[ $r == cachyos ]] || rank_repo "$r"; done
fi
log INFO "Syncing DB..."
sudo pacman -Syyq --noconfirm >/dev/null
log DONE "Mirrors updated."
