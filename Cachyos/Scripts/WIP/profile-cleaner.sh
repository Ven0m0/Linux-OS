#!/bin/bash
# shellcheck disable=2034,2155
# Compact Profile Cleaner - Optimized

: "${XDG_CONFIG_HOME:=$HOME/.config}" "${XDG_DATA_HOME:=$HOME/.local/share}"
VERSION="2.0" CONFIG="$XDG_CONFIG_HOME/profile-cleaner.conf"
[[ -f $CONFIG ]] && . "$CONFIG"
if [[ ${COLORS:-dark} == "dark" ]]; then
  BLD="\e[1m" RED="\e[1;31m" GRN="\e[1;32m" YLW="\e[1;33m" NRM="\e[0m"
else
  BLD="\e[1m" RED="\e[0;31m" GRN="\e[0;32m" YLW="\e[0;34m" NRM="\e[0m"
fi
printf "${BLD}profile-cleaner v%s${NRM}\n\n" "$VERSION"
for cmd in bc find parallel sqlite3 xargs file; do
  command -v "$cmd" >/dev/null || {
    echo >&2 "Missing: $cmd"
    exit 1
  }
done
export GRN YLW NRM
do_clean_file() {
  local db="$1" bsize=$(du -b "$db" | cut -f1)
  printf "${GRN} Cleaning${NRM} %s" "${db##*/}"
  sqlite3 "$db" "VACUUM; REINDEX;"
  local asize=$(du -b "$db" | cut -f1) saved=$(echo "scale=2; ($bsize-$asize)/1048576" | bc)
  printf "\r\033[K${GRN} Done${NRM} -${YLW}%s${NRM} MB\n" "$saved"
}
export -f do_clean_file
find_dbs() {
  find -L "$@" -maxdepth 2 -type f -not -name '*.sqlite-wal' -print0 2>/dev/null \
    | xargs -0 file -e ascii | sed -n 's/:.*SQLite.*//p'
}
scan_and_clean() {
  local type="$1" name="$2" base="$3" paths_to_clean=()
  shift 3
  local subdirs=("$@")
  printf " ${YLW}Checking %s...${NRM}\n" "$name"
  if [[ $type == "chrome" ]]; then
    for dir in "${subdirs[@]}"; do [[ -d "$base/$dir" ]] && paths_to_clean+=("$base/$dir"); done
    [[ ${#paths_to_clean[@]} -eq 0 ]] && {
      echo -e "${RED}Error: No profiles found for $name${NRM}"
      exit 1
    }
  elif [[ $type == "mozilla" ]]; then
    [[ ! -d $base || ! -f "$base/profiles.ini" ]] && {
      echo -e "${RED}Error: Invalid path or profiles.ini missing${NRM}"
      exit 1
    }
    while read -r line; do
      local p="${line#*=}"
      [[ -d "$base/$p" ]] && paths_to_clean+=("$base/$p") || paths_to_clean+=("$p")
    done < <(grep '^[Pp]ath=' "$base/profiles.ini" | tr -d '\r')
  elif [[ $type =~ ^(path|simple)$ ]]; then
    [[ $type == "simple" && -d $base ]] && paths_to_clean+=("$base")
    [[ $type == "path" ]] && for p in "$base" "${subdirs[@]}"; do [[ -d $p ]] && paths_to_clean+=("$p"); done
    [[ ${#paths_to_clean[@]} -eq 0 ]] && {
      echo -e "${RED}Error: Invalid path(s)${NRM}"
      exit 1
    }
  fi
  mapfile -t targets < <(find_dbs "${paths_to_clean[@]}")
  [[ ${#targets[@]} -eq 0 ]] && return
  local start=$(du -b -c "${targets[@]}" | tail -n 1 | cut -f 1)
  SHELL=/bin/bash parallel --gnu -k --bar do_clean_file ::: "${targets[@]}" 2>/dev/null
  local end=$(du -b -c "${targets[@]}" | tail -n 1 | cut -f 1)
  printf "\n${BLD}Total reduced by ${YLW}%s${NRM}${BLD} MB.${NRM}\n\n" "$(echo "scale=2; ($start-$end)/1048576" | bc)"
}
case "$1" in
  B | b) scan_and_clean chrome "Brave" "$XDG_CONFIG_HOME/BraveSoftware" Brave-Browser{,-Dev,-Beta,-Nightly} ;;
  C | c) scan_and_clean chrome "Chromium" "$XDG_CONFIG_HOME" chromium{,-beta,-dev} ;;
  E | e) scan_and_clean chrome "Edge" "$XDG_CONFIG_HOME" microsoft-edge ;;
  GC | gc) scan_and_clean chrome "Chrome" "$XDG_CONFIG_HOME" google-chrome{,-beta,-unstable} ;;
  ix | IX) scan_and_clean chrome "Inox" "$XDG_CONFIG_HOME" inox ;;
  O | o) scan_and_clean chrome "Opera" "$XDG_CONFIG_HOME" opera{,-next,-developer,-beta} ;;
  V | v) scan_and_clean chrome "Vivaldi" "$XDG_CONFIG_HOME" vivaldi{,-snapshot} ;;
  F | f) scan_and_clean mozilla "Firefox" "$HOME/.mozilla/firefox" ;;
  H | h) scan_and_clean mozilla "Aurora" "$HOME/.mozilla/aurora" ;;
  I | i) scan_and_clean mozilla "Icecat" "$HOME/.mozilla/icecat" ;;
  ID | id) scan_and_clean mozilla "Icedove" "$HOME/.icedove" ;;
  L | l) scan_and_clean mozilla "Librewolf" "$HOME/.librewolf" ;;
  PM | pm) scan_and_clean mozilla "Pale Moon" "$HOME/.moonchild productions/pale moon" ;;
  S | s) scan_and_clean mozilla "Seamonkey" "$HOME/.mozilla/seamonkey" ;;
  T | t) scan_and_clean mozilla "Thunderbird" "$HOME/.thunderbird" ;;
  CK | ck) scan_and_clean mozilla "Conkeror" "$HOME/.conkeror.mozdev.org/conkeror" ;;
  FA | fa) scan_and_clean simple "Falkon" "$HOME/.config/falkon/profiles" ;;
  M | m) scan_and_clean simple "Midori" "$XDG_CONFIG_HOME/midori" ;;
  Q | q) scan_and_clean simple "QupZilla" "$HOME/.config/qupzilla/profiles" ;;
  n | N)
    nb="$HOME/.newsboat"
    [[ -d "$XDG_DATA_HOME/newsboat" ]] && nb="$XDG_DATA_HOME/newsboat"
    scan_and_clean simple "Newsboat" "$nb"
    ;;
  TO | to)
    base="$HOME/.torbrowser/profile"
    for l in de en es fr it ru; do [[ ! -d $base ]] && base="$HOME/.tor-browser-$l/INSTALL/Data/profile"; done
    scan_and_clean simple "TorBrowser" "$base"
    ;;
  P | p)
    shift
    scan_and_clean path "Custom Paths" "$@"
    ;;
  *) echo -e "Usage: $0 {b|c|e|gc|o|v|ix|f|t|l|pm|s|i|fa|m|n|to|p}" && exit 0 ;;
esac
