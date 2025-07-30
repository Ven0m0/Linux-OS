#!/usr/bin/bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit 2>/dev/null
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
echo ${HOSTNAME:-$(hostname)}
echo ${HOSTTYPE:-$(uname -m)}
echo $LANG $LC_ALL

