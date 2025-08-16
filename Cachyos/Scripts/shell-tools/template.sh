#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8
#──────────── Color & Effects ────────────
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
DEF='\e[0m'  # Reset to default
BLD='\e[1m'  #Bold
#─────────────────────────────────────────
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Validating with sudo..."
  sudo -v || { echo "Sudo failed. Exiting."; exit 1; }
fi
