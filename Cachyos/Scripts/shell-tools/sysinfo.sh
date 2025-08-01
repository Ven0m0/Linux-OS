#!/usr/bin/bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar inherit_errexit 2>/dev/null
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
echo ${HOSTNAME:-$(hostname)}
echo ${HOSTTYPE:-$(uname -m)}
echo $LANG $LC_ALL
OS="${:-$(uname -o)}"
KERNEL="$(uname -sr)"
# https://github.com/deathbybandaid/pimotd/blob/master/10logo

Running Processes..: `ps ax | wc -l | tr -d " "`

LOCALIP=ip a | grep glo | awk '{print $2}' | head -1
GLOBALIP=wget -q -O - http://icanhazip.com/ | tail
