#!/usr/bin/env bash
# apt-ultra: Unified fast APT package manager
# Combines fast-apt-mirror.sh + apt-fast functionality
# SPDX-License-Identifier: Apache-2.0
# shellcheck disable=SC2155,SC1091,SC2120
set -euo pipefail; shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"

#──────────── Constants ────────────
readonly VERSION="1.0.0"
readonly RC_INVALID_ARGS=3
readonly RC_MISC_ERROR=222
readonly LCK_FILE="/tmp/apt-ultra"
readonly LCK_FD=99

#──────────── Colors ────────────────
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

[[ !  -t 1 ]] && BLK='' RED='' GRN='' YLW='' BLU='' MGN='' CYN='' WHT='' LBLU='' PNK='' BWHT='' DEF='' BLD=''

#──────────── Helpers ──────────────
has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%b\n' "${2:-$GRN}$1$DEF" "${@:3}"; }
warn(){ msg "$*" "$YLW" >&2; }
err(){ msg "$*" "$RED" >&2; }
die(){ err "$*"; exit "${2:-1}"; }
get_priv_cmd(){
  local c
  for c in sudo-rs sudo doas; do
    has "$c" && { printf '%s' "$c"; return 0; }
  done
  [[ $EUID -eq 0 ]] || die "No privilege tool found and not root."
}
PRIV_CMD=${PRIV_CMD:-$(get_priv_cmd || true)}
run_priv(){ [[ $EUID -eq 0 || -z ${PRIV_CMD:-} ]] && "$@" || "$PRIV_CMD" -- "$@"; }
unique(){ awk '! x[$0]++'; }
max_lines(){ awk "NR<=$1"; }
matches(){ [[ $1 =~ $2 ]]; }
__xargs(){ env -i HOME="$HOME" LC_CTYPE="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" PATH="$PATH" TERM="${TERM:-}" USER="${USER:-}" xargs "$@"; }

#──────────── Config ────────────────
CONF_FILE="/etc/apt-ultra.conf"
DLDIR="/var/cache/apt/apt-ultra"
DLLIST="/tmp/apt-ultra. list"
APTCACHE="/var/cache/apt/archives"
# Defaults
_APTMGR='apt-get'
_MAXNUM=8
_MAXCONPERSRV=16
_SPLITCON=16
_MINSPLITSZ="1M"
_PIECEALGO="default"
DOWNLOADBEFORE=
APT_FAST_TIMEOUT=60
VERBOSE_OUTPUT=

# Load config if exists
[[ -f $CONF_FILE ]] && source "$CONF_FILE" || true

# Detect apt cache
eval "$(apt-config shell APTCACHE Dir::Cache::archives/d 2>/dev/null)" || true
[[ -z ${APTCACHE:-} ]] && APTCACHE="/var/cache/apt/archives"

# Aria2c downloader function
run_downloader() {
  aria2c --no-conf -c -j "$_MAXNUM" -x "$_MAXCONPERSRV" -s "$_SPLITCON" -i "$DLLIST" \
    --min-split-size="$_MINSPLITSZ" --stream-piece-selector="$_PIECEALGO" \
    --connect-timeout=600 --timeout=600 --max-connection-per-server="$_MAXCONPERSRV" \
    --uri-selector=adaptive --console-log-level=error --summary-interval=0
}

#──────────── Lock ──────────────────
CLEANUP_STATE=0

_create_lock(){
  eval "exec $LCK_FD>\"$LCK_FILE. lock\""
  flock -n "$LCK_FD" || die "apt-ultra already running!  Remove $LCK_FILE.lock if stuck."
  trap "cleanup_all; exit \$CLEANUP_STATE" EXIT
  trap "cleanup_all; exit 1" INT TERM
}
_remove_lock(){ flock -u "$LCK_FD" 2>/dev/null || :; rm -f "$LCK_FILE.lock"; }
cleanup_all(){
  local rc=$?
  [[ $CLEANUP_STATE -eq 0 ]] && CLEANUP_STATE=$rc
  [[ -f $DLLIST ]] && { mv "$DLLIST"{,.old} 2>/dev/null || rm -f "$DLLIST" 2>/dev/null || warn "Could not clean download list. "; }
  _remove_lock
}

#────────── Mirror Discovery ────────
get_dist_name(){
  if [[ -r /etc/os-release ]]; then
    (source /etc/os-release; printf '%s\n' "${ID,,}")
  elif [[ -r /etc/lsb-release ]]; then
    (source /etc/lsb-release; printf '%s\n' "${DISTRIB_ID,,}")
  else
    printf '%s\n' "${OSTYPE:-unknown}"
  fi
}

get_dist_version_name(){
  if [[ -r /etc/os-release ]]; then
    (source /etc/os-release; printf '%s\n' "${VERSION_CODENAME:-${VERSION_ID:-unknown}}")
  elif [[ -r /etc/lsb-release ]]; then
    (source /etc/lsb-release; printf '%s\n' "${DISTRIB_CODENAME:-${DISTRIB_RELEASE:-unknown}}")
  else
    printf 'unknown\n'
  fi
}

read_main_mirror_from_deb822_file(){
  [[ -f $1 ]] || return 0
  local line mirror_uri='' mirror_main=''
  while IFS= read -r line; do
    [[ -z $line ]] && { mirror_uri=; mirror_main=; continue; }
    matches "$line" 'URIs:\s+([^ ]+)' && { mirror_uri=${BASH_REMATCH[1]}; continue; }
    matches "$line" 'Components:\s+. *(main)(\s+|$)' && { mirror_main=true; continue; }
    [[ -n $mirror_uri && $mirror_main == "true" ]] && { echo "$mirror_uri"; return; }
  done < "$1"
}

get_current_mirror(){
  local dist_name=$(get_dist_name)
  case $dist_name in
    debian|kali|ubuntu|pop) ;;
    *) err "Unsupported OS: $dist_name"; return "$RC_MISC_ERROR" ;;
  esac
  local cfgfile
  case $dist_name in
    debian) cfgfile='/etc/apt/sources.list. d/debian.sources' ;;
    kali)   cfgfile='/etc/apt/sources.list' ;;
    ubuntu|pop)
      if [[ -f /etc/apt/sources.list. d/ubuntu. sources ]]; then
        cfgfile='/etc/apt/sources. list.d/ubuntu.sources'
      else
        cfgfile='/etc/apt/sources.list.d/system.sources'
      fi ;;
  esac
  local mirror=$(read_main_mirror_from_deb822_file "$cfgfile")
  if [[ -z $mirror && -f /etc/apt/sources.list ]]; then
    if grep -q -E "^deb\s+mirror\+file:/etc/apt/apt-mirrors. txt\s+.*\s+main" /etc/apt/sources. list; then
      cfgfile=/etc/apt/apt-mirrors.txt
      mirror=$(awk 'NR==1 { print $1 }' "$cfgfile")
    else
      cfgfile=/etc/apt/sources.list
      mirror=$(grep -E "^deb\s+(https?|ftp)://.*\s+main" "$cfgfile" | awk 'NR==1 { print $2 }')
    fi
  elif [[ $mirror == "mirror+file:"* ]]; then
    cfgfile=${mirror/mirror+file:/}
    mirror=$(awk 'NR==1 { print $1 }' "${mirror/mirror+file:/}")
  fi
  [[ -z $mirror ]] && { warn "Current mirror: unknown"; return; }
  msg "Current mirror: $mirror ($cfgfile)"
  [[ !  -t 1 ]] && { echo "$mirror"; echo "$cfgfile"; }
}

find_fast_mirror(){
  has curl || {
    msg "Installing curl..." "$YLW"
    run_priv apt-get -o Acquire::http::Timeout=10 update && \
    run_priv apt-get -o Acquire::http::Timeout=10 install -y --no-install-recommends curl ca-certificates || return "$RC_MISC_ERROR"
  }
  local parallel=1 healthchecks=20 speedtests=5 sample_kb=200 sample_secs=3 country= apply= exclude_current= ignore_sync= verbosity=0
  while [[ $# -gt 0 ]]; do
    case $1 in
      -p|--parallel) parallel=$2; shift ;;
      --healthchecks) healthchecks=$2; shift ;;
      --speedtests) speedtests=$2; shift ;;
      --sample-size) sample_kb=$2; shift ;;
      --sample-time) sample_secs=$2; shift ;;
      --country) country=${2^^}; shift ;;
      --apply) apply=true ;;
      --exclude-current) exclude_current=true ;;
      --ignore-sync-state) ignore_sync=true ;;
      -v|--verbose) ((verbosity++)) ;;
      --help) cat <<'EOF'
Usage: apt-ultra find-mirror [OPTIONS]
Options:
  --apply              Apply fastest mirror
  --country CODE       Country code (Ubuntu only)
  --exclude-current    Skip current mirror in tests
  --healthchecks N     Mirrors to check (default: 20)
  --speedtests N       Mirrors to speed test (default: 5)
  -p, --parallel N     Parallel tests (default: 1)
  --sample-size KB     Download size for test (default: 200)
  --sample-time SECS   Max test time (default: 3)
  -v, --verbose        More output
EOF
        return ;;
    esac
    shift
  done
  local dist_name=$(get_dist_name)
  case $dist_name in
    debian|kali|ubuntu|pop)
      local dist_version=$(get_dist_version_name)
      local dist_arch=$(dpkg --print-architecture) ;;
    *)
      local dist_name=debian dist_version=stable dist_arch=amd64 ;;
  esac
  local current_mirror=$(get_current_mirror | max_lines 1 || true)
  msg "Selecting $healthchecks random mirrors..." "$BLU"
  local mirrors= reference_mirror= last_modified_path=
  case $dist_name in
    debian)
      reference_mirror=$(curl --max-time 5 -sSL -o /dev/null http://deb.debian.org/debian -w "%{url_effective}" || echo http://deb.debian.org/debian/)
      mirrors=$(curl --max-time 5 -sSL https://www.debian.org/mirror/list 2>/dev/null | grep -Eo '(https?|ftp)://[^"]+/debian/' || true)
      [[ -z $mirrors ]] && mirrors=$reference_mirror
      last_modified_path="/dists/${dist_version}-updates/main/Contents-${dist_arch}.gz" ;;
    kali)
      reference_mirror=https://http.kali.org/
      mirrors=$(curl -sSfL https://http.kali. org/README? mirrorlist | grep -oP '(?<=README">)(https. *)(? =</a)')
      last_modified_path="/dists/${dist_version}/main/Contents-${dist_arch}.gz" ;;
    ubuntu|pop)
      if [[ $dist_arch == "arm64" || $dist_arch == "armhf" ]]; then
        reference_mirror=http://ports.ubuntu.com/ubuntu-ports/
      else
        reference_mirror=http://archive.ubuntu.com/ubuntu/
      fi
      mirrors=$(curl --max-time 5 -sSfL "http://mirrors.ubuntu.com/${country:-mirrors}. txt")
      [[ $dist_arch == "arm64" || $dist_arch == "armhf" ]] && mirrors+=$'\n'"http://ports.ubuntu.com/ubuntu-ports/"
      last_modified_path="/dists/${dist_version}-security/Contents-${dist_arch}.gz" ;;
  esac

  local preferred=("$reference_mirror")
  [[ -n $current_mirror && $exclude_current != "true" ]] && preferred+=("$current_mirror")

  mirrors=$(printf "%s\n" "${preferred[@]}")$'\n'$(echo "$mirrors" | shuf)
  mirrors=$(echo "$mirrors" | awk '{ key=$0; sub(/\/+$/, "", key); if (! seen[key]++) print }')
  [[ $exclude_current == "true" ]] && mirrors=$(echo "$mirrors" | grep -v "$current_mirror" || true)
  mirrors=$(echo "$mirrors" | unique | max_lines "$healthchecks" | sort)
  msg "✓ Selected $(echo "$mirrors" | wc -l) mirrors" "$GRN"

  [[ $verbosity -gt 1 ]] && while IFS= read -r m; do msg " → $m" "$CYN"; done <<< "$mirrors"

  msg "Health-checking mirrors..." "$BLU"
  local healthcheck_results=$(echo "$mirrors" | \
    __xargs -i -P "$(echo "$mirrors" | wc -l)" bash -c \
      'set -o pipefail
       headers=$(curl --max-time 3 -sSIL "{}'"$last_modified_path"'" 2>/dev/null || echo "CURL_ERROR")
       http_status=$(printf "%s\n" "$headers" | awk '"'"'toupper($1) ~ /^HTTP\// { code=$2 } END { print code }'"'"')
       last_modified=0; status="error"
       if [[ "$headers" == "CURL_ERROR" || -z "$http_status" ]]; then status="error"
       elif [[ "$http_status" == "404" ]]; then status="missing"
       else
         last_mod_line=$(printf "%s\n" "$headers" | grep -i "last-modified" | cut -d" " -f2- | head -n1)
         if [[ -n "$last_mod_line" ]]; then
           last_modified=$(LANG=C date -f- -u +%s <<<"$last_mod_line" 2>/dev/null || echo 0)
           [[ "$last_modified" != 0 ]] && status="ok" || status="nolastmod"
         else status="nolastmod"; fi
       fi
       echo "$last_modified $status {}"
       >&2 printf "."'
  )
  msg " ✓ done" "$GRN"

  local sorted=$(echo "$healthcheck_results" | sort -t' ' -k1,1rn -k3)
  local healthy_date=$(echo "$sorted" | awk -v ref="$reference_mirror" '$3 == ref { print $1; exit }' || true)
  [[ -z $healthy_date ]] && healthy_date=${sorted%% *}

  [[ $verbosity -gt 0 ]] && while IFS= read -r mirror; do
    local lm=${mirror%% *} rest=${mirror#* } st=${rest%% *} url=${rest#* }
    case $lm in
      "$healthy_date") msg " → UP-TO-DATE ($(date -d "@$lm" +'%Y-%m-%d %H:%M:%S %Z')) $url" "$GRN" ;;
      0) msg " → $st $url" "$YLW" ;;
      *) msg " → outdated ($(date -d "@$lm" +'%Y-%m-%d %H:%M:%S %Z')) $url" "$RED" ;;
    esac
  done <<< "$sorted"
  local healthy
  if [[ $ignore_sync == "true" ]]; then
    healthy=$(echo "$sorted" | awk '$2 != "missing" && $2 != "error" { $1=""; $2=""; sub(/^  /, ""); if ($0 != "") print }')
    msg "✓ $(echo "$healthy" | wc -l) mirrors reachable" "$GRN"
  else
    healthy=$(echo "$sorted" | awk -v d="$healthy_date" '$1 == d && $2 != "missing" && $2 != "error" { $1=""; $2=""; sub(/^  /, ""); if ($0 != "") print }')
    msg "✓ $(echo "$healthy" | wc -l) mirrors reachable & up-to-date" "$GRN"
  fi
  local speedtest_mirrors=''
  for pm in "${preferred[@]}"; do
    [[ $healthy = *"$pm"* ]] && speedtest_mirrors+=$pm$'\n'
  done
  speedtest_mirrors=$(echo "$speedtest_mirrors$healthy" | unique | max_lines "$speedtest_mirrors")
  msg "Speed testing $(echo "$speedtest_mirrors" | wc -l) mirrors (${sample_kb}KB sample)..." "$BLU"
  local sample_bytes=$((sample_kb*1024))
  local mirrors_with_speed=$(
    echo "$speedtest_mirrors" \
    | grep -v '^[[:space:]]*$' \
    | __xargs -P "$parallel" -I{} bash -c \
      "printf '%s\t%s\n' \"\$(curl -r 0-$sample_bytes --max-time $sample_secs -sS -w '%{speed_download}' -o /dev/null \"\${1}ls-lR. gz\" 2>/dev/null || echo 0)\" \"\$1\"; >&2 printf '. '" _ {} \
    | awk -F'\t' '$1 ~ /^[0-9. ]+$/ && $2 ~ /^https?:\/\// { print }' \
    | sort -rg
  )
  msg " ✓ done" "$GRN"
  [[ -z $mirrors_with_speed ]] && die "Could not determine fast mirror."
  local first="${mirrors_with_speed%%$'\n'*}"
  local fastest=$(echo "$first" | awk -F'\t' '{ print $2 }')
  local speed=$(echo "$first" | awk -F'\t' '{ print $1 }' | numfmt --to=iec --suffix=B/s)
  [[ !  $fastest =~ ^https?:// ]] && die "Invalid fastest mirror: $fastest"
  [[ $verbosity -gt 0 ]] && echo "$mirrors_with_speed" | tail -n +2 | tac | while IFS= read -r m; do
    local sp=$(echo "${m%%$'\n'*}" | awk -F'\t' '{ print $1 }' | numfmt --to=iec --suffix=B/s)
    msg " → $(echo "$m" | awk -F'\t' '{ print $2 }') ($sp)" "$CYN"
  done
  msg "✓ Fastest: $fastest ($speed)" "$LBLU$BLD"
  [[ $apply == "true" ]] && set_mirror "$fastest" || :
  [[ !  -t 1 ]] && echo "$fastest"
}

set_mirror(){
  local new_mirror=${1:? }
  matches "${new_mirror,,}" '^(https?|ftp)://' || die "Malformed URL: $new_mirror"
  local dist_name=$(get_dist_name)
  case $dist_name in
    debian|kali|ubuntu|pop) ;;
    *) die "Unsupported OS: $dist_name" ;;
  esac

  local current
  readarray -t current < <(get_current_mirror || true)
  [[ ${#current[@]} -lt 1 ]] && die "Cannot determine current mirror."
  if [[ ${current[0]} == "$new_mirror" ]]; then
    msg "Already using: $new_mirror" "$GRN"
  else
    local backup="${current[1]}. $(date +'%Y%m%d_%H%M%S'). save"
    msg "Creating backup: $backup" "$YLW"
    run_priv cp "${current[1]}" "$backup"
    msg "Changing mirror from [${current[0]}] to [$new_mirror]..." "$BLU"
    run_priv sed -i \
      -e "s|${current[0]}\$|$new_mirror|g" \
      -e "s|${current[0]} |$new_mirror |g" \
      -e "s|${current[0]}\t|$new_mirror\t|g" \
      "${current[1]}"
    run_priv apt-get -o Acquire::http::Timeout=10 update
    msg "✓ Mirror changed successfully" "$GRN"
  fi
}

#────────── APT Operations ──────────
urldecode(){ printf '%b' "${1//%/\\x}"; }
get_uris(){
  [[ !  -d $(dirname "$DLLIST") ]] && { mkdir -p "$(dirname "$DLLIST")" || die "Cannot create download dir. "; }
  [[ -f $DLLIST ]] && { rm -f "$DLLIST" 2>/dev/null || die "Cannot write to $DLLIST"; }
  echo "# apt-ultra download list: $(date)" > "$DLLIST"
  local uri_mgr="$_APTMGR"
  case "$(basename "$_APTMGR")" in
    apt|apt-get) uri_mgr="$_APTMGR" ;;
    *) uri_mgr='apt-get' ;;
  esac
  local uris_full=$("$uri_mgr" -y --print-uris "$@" 2>&1)
  CLEANUP_STATE=$?
  [[ $CLEANUP_STATE -ne 0 ]] && { err "Package manager failed. "; return; }
  local DOWNLOAD_SIZE=0
  while IFS=' ' read -r uri filename filesize _; do
    [[ -z $uri ]] && continue
    uri="${uri//\'}"
    local fname_dec=$(urldecode "$filename")
    IFS='_' read -r pkg ver _ <<<"$fname_dec"
    DOWNLOAD_SIZE=$((DOWNLOAD_SIZE + filesize))
    {
      echo "$uri"; echo " out=$filename"
    } >> "$DLLIST"
  done <<<"$(echo "$uris_full" | grep -E "^'(https?|ftp)://")"
  msg "Download size: $(echo "$DOWNLOAD_SIZE" | numfmt --to=iec-i --suffix=B)" "$LBLU"
}

#────────── Main ────────────────────
usage(){
  cat <<EOF
${LBLU}apt-ultra${DEF} v${VERSION} - Fast APT package manager

${BLD}Usage:${DEF}
  apt-ultra <command> [options] [packages...]

${BLD}Commands:${DEF}
  install, upgrade, full-upgrade, dist-upgrade, build-dep
    Install/upgrade packages with parallel downloads

  find-mirror [--apply] [--verbose]
    Find fastest mirror (optionally apply)

  set-mirror <URL>
    Set APT mirror to URL

  current-mirror
    Show current mirror

  clean, autoclean
    Clean package cache

${BLD}Environment:${DEF}
  Config: ${CONF_FILE}
  Cache: ${DLDIR}
  Backends: aria2c → apt-fast → nala → apt-get

${BLD}Examples:${DEF}
  apt-ultra install nginx
  apt-ultra find-mirror --apply
  apt-ultra upgrade -y
EOF
}

main(){
  _create_lock
  local cmd=${1:-}
  [[ $cmd == "--help" || $cmd == "-h" || -z $cmd ]] && { usage; exit 0; }
  case $cmd in
    find-mirror) shift; find_fast_mirror "$@" ;;
    set-mirror) shift; set_mirror "$@" ;;
    current-mirror) get_current_mirror | max_lines 1 ;;
    install|upgrade|full-upgrade|dist-upgrade|build-dep)
      if has aria2c; then
        msg "Fetching package URIs..." "$BLU"
        get_uris "$@"
        if [[ -f $DLLIST && $(wc -l < "$DLLIST") -gt 1 ]]; then
          [[ !  -d $DLDIR ]] && mkdir -p "$DLDIR"
          cd "$DLDIR" || die "Cannot cd to $DLDIR"
          run_downloader
          find . -type f \( -name '*.deb' -o -name '*.ddeb' \) -execdir mv -ft "$APTCACHE" {} + 2>/dev/null || :
          for x in *.aria2; do rm -f "$x" "${x%.aria2}"; done
          cd - &>/dev/null || :
        fi
        run_priv "$_APTMGR" "$@"
      elif has apt-fast; then
        msg "Falling back to apt-fast..." "$YLW"
        run_priv apt-fast "$@"
      elif has nala; then
        msg "Falling back to nala..." "$YLW"
        run_priv nala "$@"
      else
        msg "Falling back to apt-get..." "$YLW"
        run_priv apt-get "$@"
      fi ;;
    clean|autoclean)
      run_priv "$_APTMGR" "$@"
      [[ -d $DLDIR ]] && { find "$DLDIR" -maxdepth 1 -type f -delete; rm -f "$DLLIST"* 2>/dev/null || :; } ;;
    *) run_priv "$_APTMGR" "$@" ;;
  esac
}

main "$@"
