#!/usr/bin/env bash
# shellcheck shell=bash
set -eECuo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# shopt -s extglob
LC_COLLATE=C LC_CTYPE=C.UTF-8 LANG=C.UTF-8

#----------------------------------------|
# Color
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
# Effects
DEF='\e[0m'   #Default color and effects
BLD='\e[1m'   #Bold\brighter  
#----------------------------------------|

sudo -v

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo $WORKDIR
cd $WORKDIR



