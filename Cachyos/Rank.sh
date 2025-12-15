#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}"
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

# Config
MIRRORDIR="/etc/pacman.d"
GPGCONF="$MIRRORDIR/gnupg/gpg.conf"
BACKUPDIR="$MIRRORDIR/.bak"
LOGFILE="/var/log/mirror-rank.log"
# Country: Auto-detect with 'DE' fallback
COUNTRY="${RATE_MIRRORS_ENTRY_COUNTRY:-$(curl -sf https://ipapi.co/country_code || echo DE)}"
[[ -n $COUNTRY ]] || COUNTRY="DE"
ARCHLIST_URL_GLOBAL="https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
ARCHLIST_URL_DE="https://archlinux.org/mirrorlist/?country=DE&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
REPOS=(cachyos chaotic-aur endeavouros alhp)
KEYSERVERS=( # We want to use keyservers only with secured (hkps or https) connections!
  ############ These don't seem to work:
  ## "pgp.mit.edu"
  #  "keyring.debian.org"
  ## "subset.pool.sks-keyservers.net"
  #  "ipv6.pool.sks-keyservers.net"
  # hkps://keys.mailvelope.com
  ## hkps://hkps.pool.sks-keyservers.net
  # hkps://attester.flowcrypt.com
  ############ These do seem to work:
  "hkps://keys.openpgp.org"
  "hkps://keyserver.ubuntu.com"
  "hkps://zimmermann.mayfirst.org"
  # "https://keyserver.ubuntu.com"
  # "https://zimmermann.mayfirst.org"
  ############ These seem to work but only with hkp:
  # "hkp://ipv4.pool.sks-keyservers.net"
  # "hkp://pool.sks-keyservers.net"
  # "hkp://na.pool.sks-keyservers.net"
  # "hkp://eu.pool.sks-keyservers.net"
  # "hkp://oc.pool.sks-keyservers.net"
  # "hkp://p80.pool.sks-keyservers.net"
  # hkp://hkps.pool.sks-keyservers.net
)
# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[1;33m' CYN=$'\e[36m' DEF=$'\e[0m' BLD=$'\e[1m'
# Helpers
has() { command -v "$1" &>/dev/null; }
xecho() { printf '%b\n' "$*"; }
log() { xecho "${GRN}${BLD}[${1:-INFO}]${DEF} ${*:2}" | tee -a "$LOGFILE"; }
warn() { xecho "${YLW}${BLD}[!]${DEF} $*" >&2; }
err() { xecho "${RED}${BLD}[-]${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}
backup() {
  [[ -f $1 ]] || return 0
  mkdir -p "$BACKUPDIR"
  cp -a "$1" "$BACKUPDIR/${1##*/}-$(printf '%s' "$EPOCHSECONDS").bak"
  find "$BACKUPDIR" -name "${1##*/}-*.bak" -printf '%T@ %p\n' | sort -rn | tail -n+6 | awk '{print $2}' | xargs -r rm -f
}

# Actions
rank_keys() {
  [[ -f $GPGCONF ]] || return 0
  log KEY "Ranking keyservers..."
  backup "$GPGCONF"
  local best="" min=9999 start_ts end_ts t1 t2
  for u in "${KEYSERVERS[@]}"; do
    local test_url="${u/hkp/http}"
    test_url="${test_url/http:/http:}"
    # Perf: Native Bash timing
    printf -v start_ts "%.3f" "$EPOCHREALTIME"
    t1="${start_ts/./}"
    if curl -sI -m2 "$test_url" &>/dev/null; then
      printf -v end_ts "%.3f" "$EPOCHREALTIME"
      t2="${end_ts/./}"
      local diff=$((t2 - t1))
      if ((diff < min)); then
        min=$diff
        best=$u
      fi
    fi
  done
  if [[ -n $best ]]; then
    log KEY "Best: $best ($min ms)"
    sed -i "s|^[[:space:]]*keyserver .*|keyserver $best|" "$GPGCONF"
  else
    warn "No keyservers reachable."
  fi
}

rank_repo() {
  local name=$1 file="$MIRRORDIR/${1}-mirrorlist"
  [[ -f $file ]] || return 0
  log REPO "Ranking $name..."
  backup "$file"
  local tmp
  tmp=$(mktemp)
  # Pipe URLs directly to rate-mirrors stdin
  if grep -oP 'https?://[^ ]+' "$file" | sort -u | rate-mirrors --save="$tmp" --entry-country="$COUNTRY" stdin \
    --fetch-mirrors-timeout=5000 --path-to-return='$repo/os/$arch' &>/dev/null; then
    install -m644 "$tmp" "$file"
  else
    warn "Failed to rank $name"
  fi
  rm -f "$tmp"
}

rank_arch() {
  local file="$MIRRORDIR/mirrorlist" url="$ARCHLIST_URL_GLOBAL"
  [[ $COUNTRY == "DE" ]] && url="$ARCHLIST_URL_DE"
  log ARCH "Fetching latest Arch mirrors ($COUNTRY)..."
  backup "$file"
  local tmp
  tmp=$(mktemp)
  if ! curl -sfL "$url" -o "$tmp.mlst"; then
    warn "Failed to download Arch mirrorlist"
    rm -f "$tmp" "$tmp.mlst"
    return 1
  fi # Uncomment servers using sed
  sed -E 's|^##[ ]*Server|Server|' "$tmp.mlst" >"$tmp.raw"
  # Rank
  if rate-mirrors --save="$tmp" --entry-country="$COUNTRY" --top-mirrors-number-to-retest=5 arch --file "$tmp.raw" &>/dev/null; then
    install -m644 "$tmp" "$file"
  else
    warn "rate-mirrors failed for Arch"
  fi
  rm -f "$tmp" "$tmp.mlst" "$tmp.raw"
}

# Main Execution
log INFO "Country: $COUNTRY | Tool: rate-mirrors"
rank_keys || :
if has cachyos-rate-mirrors; then
  log CACHY "Using cachyos-rate-mirrors wrapper..."
  cachyos-rate-mirrors
else
  # Manual Fallback Logic
  rank_repo "cachyos"
  rank_arch
  for r in "${REPOS[@]}"; do
    [[ $r == cachyos ]] || rank_repo "$r"
  done
fi
log INFO "Syncing DB..."
sudo pacman -Syyq --noconfirm &>/dev/null
log DONE "Mirrors updated."
