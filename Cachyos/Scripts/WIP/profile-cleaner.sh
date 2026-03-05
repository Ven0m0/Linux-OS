#!/usr/bin/env bash
# Profile Cleaner v3.0 — SQLite VACUUM/REINDEX for browser profiles
# Merged: profile-cleaner.sh + browser-vacuum.sh
# Targets: Firefox, Chromium, and derivatives
set -euo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

: "${XDG_CONFIG_HOME:=$HOME/.config}" "${XDG_DATA_HOME:=$HOME/.local/share}"

# Colors (trans palette)
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
BLD=$'\e[1m' RED=$'\e[1;31m' GRN=$'\e[1;32m' YLW=$'\e[1;33m' DEF=$'\e[0m'

has(){ command -v "$1" &>/dev/null; }
log(){ printf '%b\n' "$*"; }
warn(){ log "${YLW}WARN:${DEF} $*"; }
err(){ log "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; exit "${2:-1}"; }

has sqlite3 || die "sqlite3 required"

TOTAL_SAVED=0

# --- Core: find SQLite DBs ---
find_dbs(){
  find -L "$@" -maxdepth 2 -type f \
    ! -name '*.sqlite-wal' ! -name '*.sqlite-shm' \
    -print0 2>/dev/null \
    | xargs -0 -r file -e ascii 2>/dev/null \
    | sed -n 's/:.*SQLite.*//p'
}

# --- Core: vacuum a single DB ---
vacuum_db(){
  local db=${1:?} bsize asize saved
  bsize=$(stat -c%s "$db" 2>/dev/null) || return 0
  sqlite3 "$db" "VACUUM; REINDEX;" 2>/dev/null || {
    warn "failed to vacuum ${db##*/}"
    return 0
  }
  asize=$(stat -c%s "$db")
  saved=$(( (bsize - asize) / 1024 ))
  TOTAL_SAVED=$(( TOTAL_SAVED + (saved > 0 ? saved : 0) ))

  local indicator
  if (( saved > 0 )); then
    indicator="${YLW}-${saved}${DEF} KB"
  elif (( saved < 0 )); then
    indicator="${RED}+$(( saved * -1 ))${DEF} KB"
  else
    indicator="${YLW}~${DEF}"
  fi
  log "  ${GRN}✓${DEF} ${db##*/}  ${indicator}"
}

# --- Core: clean all DBs in given paths ---
clean_paths(){
  local -a paths=("$@")
  local -a targets
  mapfile -t targets < <(find_dbs "${paths[@]}")
  (( ${#targets[@]} )) || return 0

  local db
  for db in "${targets[@]}"; do
    vacuum_db "$db"
  done
}

# --- Wait for browser process to exit ---
wait_for_exit(){
  local name=${1:?} user=${2:-$USER} pid i=6
  pid=$(pgrep -u "$user" "$name" 2>/dev/null) || return 0
  printf '  Waiting for %s to exit' "$name"
  while kill -0 "$pid" 2>/dev/null; do
    if (( i == 0 )); then
      read -rp " kill it? [y/N]: " ans
      if [[ ${ans,,} == @(y|yes) ]]; then
        kill -TERM "$pid" 2>/dev/null || :
        sleep 3
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || :
        break
      fi
      return 1
    fi
    printf '.'; sleep 2; (( i-- ))
  done
  printf '\n'
}

# --- Resolve profile dirs by type ---
resolve_profiles(){
  local type=${1:?} base=${2:?}
  shift 2
  local -a subdirs=("$@")

  case $type in
    chrome)
      local dir
      for dir in "${subdirs[@]}"; do
        [[ -d $base/$dir ]] || continue
        # Chrome profiles: Default, Profile 1, etc.
        local p
        for p in "$base/$dir"/Default "$base/$dir"/Profile*; do
          [[ -d $p ]] && printf '%s\n' "$p"
        done
      done
      ;;
    mozilla)
      [[ -f $base/profiles.ini ]] || return 0
      local line path
      while IFS= read -r line; do
        path=${line#*=}
        path=${path%$'\r'}
        if [[ -d $base/$path ]]; then
          printf '%s\n' "$base/$path"
        elif [[ -d $path ]]; then
          printf '%s\n' "$path"
        fi
      done < <(sed -n 's/^[Pp]ath=//p' "$base/profiles.ini")
      ;;
    simple)
      [[ -d $base ]] && printf '%s\n' "$base"
      ;;
    path)
      local p
      for p in "$base" "${subdirs[@]}"; do
        [[ -d $p ]] && printf '%s\n' "$p"
      done
      ;;
  esac
}

# --- Main scan & clean for a browser ---
scan_and_clean(){
  local type=${1:?} name=${2:?} base=${3:?}
  shift 3
  local -a subdirs=("$@") profiles

  log "${LBLU}▸${DEF} ${BLD}${name}${DEF}"

  mapfile -t profiles < <(resolve_profiles "$type" "$base" "${subdirs[@]}")
  if (( ! ${#profiles[@]} )); then
    log "  ${RED}no profiles found${DEF}"
    return 0
  fi

  # Wait for browser if chrome/mozilla
  local proc_name=${name,,}
  proc_name=${proc_name// /-}
  [[ $type == @(chrome|mozilla) ]] && wait_for_exit "$proc_name"

  local p
  for p in "${profiles[@]}"; do
    log "  ${PNK}[${p##*/}]${DEF}"
    clean_paths "$p"
  done
}

# --- Auto-scan: detect all installed browsers ---
auto_scan(){
  local user=${1:-$USER} home=${2:-$HOME}
  local cfg="${home}/.config"

  # Mozilla-family
  local -A mozilla_browsers=(
    [firefox]="$home/.mozilla/firefox"
    [librewolf]="$home/.librewolf"
    [thunderbird]="$home/.thunderbird"
    [seamonkey]="$home/.mozilla/seamonkey"
    [icecat]="$home/.mozilla/icecat"
    [aurora]="$home/.mozilla/aurora"
    [pale-moon]="$home/.moonchild productions/pale moon"
  )

  local name base
  for name in "${!mozilla_browsers[@]}"; do
    base=${mozilla_browsers[$name]}
    [[ -f $base/profiles.ini ]] && scan_and_clean mozilla "$name" "$base"
  done

  # Chromium-family
  local -A chrome_browsers=(
    [chromium]="chromium chromium-beta chromium-dev"
    [google-chrome]="google-chrome google-chrome-beta google-chrome-unstable"
    [brave]="BraveSoftware/Brave-Browser BraveSoftware/Brave-Browser-Beta"
    [vivaldi]="vivaldi vivaldi-snapshot"
    [edge]="microsoft-edge microsoft-edge-beta"
    [opera]="opera opera-next opera-developer"
  )

  for name in "${!chrome_browsers[@]}"; do
    local -a dirs
    read -ra dirs <<< "${chrome_browsers[$name]}"
    local found=0 d
    for d in "${dirs[@]}"; do
      [[ -d $cfg/$d/Default ]] && { found=1; break; }
    done
    (( found )) && scan_and_clean chrome "$name" "$cfg" "${dirs[@]}"
  done

  # Standalone
  [[ -d $cfg/falkon/profiles ]] && scan_and_clean simple falkon "$cfg/falkon/profiles"
}

# --- Multi-user support (sudo) ---
run_for_users(){
  local -a users
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    mapfile -t users < <(find /home -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
  else
    users=("$USER")
  fi

  local user
  for user in "${users[@]}"; do
    log "${BWHT}━━━ ${BLD}${user}${DEF} ${BWHT}━━━${DEF}"
    auto_scan "$user" "/home/$user"
  done
}

usage(){
  cat -s <<'EOF'
Profile Cleaner v3.0 — SQLite VACUUM/REINDEX for browser profiles

Usage: profile-cleaner.sh [OPTION]

Browsers:
  a, auto     Auto-detect all browsers (default)
  f           Firefox          l   Librewolf
  gc          Google Chrome    c   Chromium
  b           Brave            v   Vivaldi
  e           Edge             o   Opera
  t           Thunderbird      s   Seamonkey
  i           Icecat           pm  Pale Moon
  fa          Falkon           m   Midori
  n           Newsboat         to  Tor Browser
  p PATH...   Custom path(s)

Options:
  -h, --help     Show this help
  --version      Show version

Run as root to clean all users.
EOF
}

main(){
  case ${1:-auto} in
    -h|--help) usage; exit 0;;
    --version) printf 'profile-cleaner 3.0\n'; exit 0;;
    a|auto) run_for_users;;
    b) scan_and_clean chrome Brave "$XDG_CONFIG_HOME/BraveSoftware" Brave-Browser{,-Dev,-Beta,-Nightly};;
    c) scan_and_clean chrome Chromium "$XDG_CONFIG_HOME" chromium{,-beta,-dev};;
    e) scan_and_clean chrome Edge "$XDG_CONFIG_HOME" microsoft-edge{,-beta};;
    gc) scan_and_clean chrome Chrome "$XDG_CONFIG_HOME" google-chrome{,-beta,-unstable};;
    o) scan_and_clean chrome Opera "$XDG_CONFIG_HOME" opera{,-next,-developer,-beta};;
    v) scan_and_clean chrome Vivaldi "$XDG_CONFIG_HOME" vivaldi{,-snapshot};;
    f) scan_and_clean mozilla Firefox "$HOME/.mozilla/firefox";;
    i) scan_and_clean mozilla Icecat "$HOME/.mozilla/icecat";;
    l) scan_and_clean mozilla Librewolf "$HOME/.librewolf";;
    pm) scan_and_clean mozilla "Pale Moon" "$HOME/.moonchild productions/pale moon";;
    s) scan_and_clean mozilla Seamonkey "$HOME/.mozilla/seamonkey";;
    t) scan_and_clean mozilla Thunderbird "$HOME/.thunderbird";;
    fa) scan_and_clean simple Falkon "$HOME/.config/falkon/profiles";;
    m) scan_and_clean simple Midori "$XDG_CONFIG_HOME/midori";;
    n)
      local nb="$HOME/.newsboat"
      [[ -d $XDG_DATA_HOME/newsboat ]] && nb="$XDG_DATA_HOME/newsboat"
      scan_and_clean simple Newsboat "$nb"
      ;;
    to)
      local base="$HOME/.torbrowser/profile"
      local lang
      for lang in de en es fr it ru; do
        [[ -d $base ]] && break
        base="$HOME/.tor-browser-$lang/INSTALL/Data/profile"
      done
      scan_and_clean simple TorBrowser "$base"
      ;;
    p)
      shift
      (( $# )) || die "Usage: $0 p PATH [PATH...]"
      scan_and_clean path "Custom" "$@"
      ;;
    *) usage; die "unknown option: $1";;
  esac

  printf '\n'
  if (( TOTAL_SAVED > 0 )); then
    log "${GRN}Total saved:${DEF} ${YLW}${TOTAL_SAVED}${DEF} KB"
  else
    log "Nothing to reclaim."
  fi
}

main "$@"
