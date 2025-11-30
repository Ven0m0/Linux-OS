#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C

MIRRORDIR="/etc/pacman.d"
GPGCONF="$MIRRORDIR/gnupg/gpg.conf"
BACKUPDIR="$MIRRORDIR/.bak"
KEYRANK_LOG="$BACKUPDIR/keyserver-bench-$(printf '%s' "$EPOCHSECONDS").log"

KEYSERVERS=(
  "hkp://keyserver.ubuntu.com"
  "hkps://keys.openpgp.org"
  "hkps://pgp.mit.edu"
  "hkp://keys.gnupg.net"
  "hkps://keyserver.ubuntu.com"
)
TIMEOUT=3
MIN_ATTEMPTS=2
MAX_ATTEMPTS=5
_log(){ printf '\e[1;36m[KEYRANK]\e[0m %s\n' "$*" >&2; }
_warn(){ printf '\e[1;33m[KEYRANK:WARN]\e[0m %s\n' "$*" >&2; }
_err(){ printf '\e[1;31m[KEYRANK:ERR]\e[0m %s\n' "$*" >&2; }

backup_gpgconf(){
  [[ -f $GPGCONF ]] || return
  mkdir -p "$BACKUPDIR"
  cp -a "$GPGCONF" "$BACKUPDIR/gpg.conf-$(printf '%s' "$EPOCHSECONDS").bak"
  # keep six recent
  find "$BACKUPDIR" -name 'gpg.conf-*.bak' -printf '%T@ %p\n' | sort -rn | tail -n+7 | awk '{print $2}' | xargs -r rm -f
}
is_gpgconf_valid(){ grep -qE '^[[:space:]]*keyserver ' "$GPGCONF" 2>/dev/null; }
test_keyserver_latency(){
  local s=$1 a=${2:-$MIN_ATTEMPTS} u="${s/hkp/http}" t1 t2 ms_sum=0 count=0 start_ts end_ts
  # Native loop instead of seq
  for ((n=1; n<=a; n++)); do
    # Use printf to format float EPOCHREALTIME to 3 decimal places (ms), then strip dot
    printf -v start_ts "%.3f" "${EPOCHREALTIME}"
    t1="${start_ts/./}"
    
    if curl -fso /dev/null -m "$TIMEOUT" --retry 1 --connect-timeout "$TIMEOUT" "$u"; then
      printf -v end_ts "%.3f" "${EPOCHREALTIME}"
      t2="${end_ts/./}"
      
      ms_sum=$((ms_sum + t2 - t1))
      count=$((count + 1))
    fi
  done
  [[ $count -gt 0 ]] && printf '%s %d\n' "$s" "$((ms_sum / count))"
}

rank_keyservers(){
  [[ -f $GPGCONF ]] || { _warn "gpg.conf not found, skipping"; return 1; }
  backup_gpgconf
  _log "Testing reachability and latency for keyservers..."
  declare -a scores
  for s in "${KEYSERVERS[@]}"; do
    local line
    line=$(test_keyserver_latency "$s" $MAX_ATTEMPTS 2>>"$KEYRANK_LOG") || :
    [[ $line ]] && scores+=("$line")
  done
  if ((${#scores[@]}==0)); then
    _warn "All keyservers failed; not updating config."; return 2
  fi
  printf "%s\n" "${scores[@]}" | sort -k2,2n | tee -a "$KEYRANK_LOG"
  local best
  best=$(printf "%s\n" "${scores[@]}" | sort -k2,2n | head -n1 | awk '{print $1}')
  [[ $best ]] || { _err "No reachable keyserver after ranking"; return 3; }
  if [[ "$(grep -m1 -E '^[[:space:]]*keyserver ' "$GPGCONF" | awk '{print $2}')" == "$best" ]]; then
    _log "Keyserver unchanged ($best)"; return 0
  fi
  _log "Updating gpg.conf: keyserver $best"
  sed -i -E "s|^[[:space:]]*keyserver .*|keyserver $best|" "$GPGCONF" || {
    _err "sed failed, manual intervention required"; return 5
  }
  if ! is_gpgconf_valid; then
    cp "$BACKUPDIR/gpg.conf-"*".bak" "$GPGCONF" 2>/dev/null || _err "restore failed"
    _err "Config invalid; restored previous backup"; return 6
  fi
  _log "Keyserver ranking done. Selected: $best"
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && rank_keyservers
