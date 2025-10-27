#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#─────────────────────────────────────────
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Validating with sudo..."
  sudo -v || {
    echo "Sudo failed. Exiting."
    exit 1
  }
fi
