#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
has() { command -v -- "$1" &>/dev/null; }
[[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :

BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Main blocklist functionality using hblock
main() {
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
    hblock_temp=$(mktemp -t hblock)
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
      rm -f "$hblock_temp"
      return 1
    fi
  fi
}

# Run main function with all arguments
main "$@"
