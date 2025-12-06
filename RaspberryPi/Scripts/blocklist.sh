#!/usr/bin/env bash
# This script manages ad/tracker blocklists using hblock
# ============ Inlined from lib/common.sh ============
set -euo pipefail; shopt -s nullglob globstar extglob; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
cd "$(cd "$( dirname "${BASH_SOURCE[0]}" )" &>/dev/null && pwd -P)" || exit 1
has(){ command -v -- "$1" &> /dev/null; }
[[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &> /dev/null || :
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2> /dev/null || shift $#
  if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; else
    local find_type_arg
    case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac
    if [[ -n $action ]]; then find "$search_path" "$find_type_arg" -name "$pattern" "$action" "$@"; else find "$search_path" "$find_type_arg" -name "$pattern"; fi
  fi
}
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
remove_comments(){ sed -e 's/[[:blank:]]*#.*//;/^$/d'; }
removeComments(){ remove_comments; }
remove_duplicate_lines(){ if [[ -n ${1:-} && -f $1 ]]; then awk '!seen[$0]++' "$1"; else awk '!seen[$0]++'; fi; }
remove_duplicate_lines_sorted(){ if [[ -n ${1:-} && -f $1 ]]; then sort -u "$1"; else sort -u; fi; }
remove_trailing_spaces(){ awk '{gsub(/^ +| +$/,"")}1'; }
remove_blank_lines(){ sed '/^$/d'; }
remove_multiple_blank_lines(){ sed '/^$/N;/^$/D'; }
to_lowercase(){ tr '[:upper:]' '[:lower:]'; }
to_uppercase(){ tr '[:lower:]' '[:upper:]'; }
remove_colors(){ sed 's/\[[0-9;]*m//g'; }
extract_pattern(){ local pattern="$1"; shift; grep -E "$pattern" "$@"; }
extract_urls(){ grep -oE '(https?|ftp)://[^[:space:]]+' "$@"; }
extract_ips(){ grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$@"; }
count_lines(){ grep -c . "$@" 2> /dev/null || echo 0; }
normalize_whitespace(){ sed -e 's/	/ /g' -e 's/  */ /g'; }
display_banner(){
  local banner_text="$1"; shift
  local -a flag_colors=("$@")
  if ((${#flag_colors[@]} == 0)); then flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"); fi
  mapfile -t banner_lines <<< "$banner_text"
  local lines=${#banner_lines[@]}
  local segments=${#flag_colors[@]}
  if ((lines <= 1)); then for line in "${banner_lines[@]}"; do printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"; done; else for i in "${!banner_lines[@]}"; do
    local segment_index=$((i * (segments - 1) / (lines - 1)))
    ((segment_index >= segments)) && segment_index=$((segments - 1))
    printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
  done; fi
}
# https://github.com/hectorm/hblock/blob/master/hblock
# Remove comments from string (function already defined in lib/text.sh above)
# removeComments(){ sed -e 's/[[:blank:]]*#.*//;/^$/d'; }
# Remove reserved Top Level Domains
removeReservedTLDs(){
  sed -e '/\.corp$/d' \
    -e '/\.domain$/d' \
    -e '/\.example$/d' \
    -e '/\.home$/d' \
    -e '/\.host$/d' \
    -e '/\.invalid$/d' \
    -e '/\.lan$/d' \
    -e '/\.local$/d' \
    -e '/\.localdomain$/d' \
    -e '/\.localhost$/d' \
    -e '/\.test$/d'
}
# Main blocklist functionality using hblock
main(){
  local hblock_url='https://raw.githubusercontent.com/hectorm/hblock/master/hblock'
  local hblock_temp
  echo "${BLD}${CYN}Blocklist Manager${DEF}"
  echo "Using hblock for ad/tracker blocking"
  echo ""
  # Check if hblock is installed
  if has hblock; then
    echo "${GRN}✓${DEF} hblock is installed"
    echo "Running hblock..."
    sudo hblock "$@"
  else
    echo "${YLW}⚠${DEF} hblock is not installed"
    echo "Downloading and running hblock temporarily..."
    hblock_temp=$(mktemp /tmp/hblock.XXXXXX)
    if curl -fsSL "$hblock_url" -o "$hblock_temp"; then
      echo "${GRN}✓${DEF} Downloaded hblock successfully"
      chmod +x "$hblock_temp"
      sudo bash "$hblock_temp" "$@"
      rm -f "$hblock_temp"
      echo ""
      echo "To install hblock permanently, visit: https://github.com/hectorm/hblock"
    else
      echo "${RED}✗${DEF} Failed to download hblock"
      echo "Please install hblock manually or check your internet connection"
      rm -f "$hblock_temp"; return 1
    fi
  fi
}

# Run main function with all arguments
main "$@"
