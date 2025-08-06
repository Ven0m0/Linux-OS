#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
IFS=$'\n\t'

#──────────── Color & Effects ────────────
DEF='\e[0m'   # Default / Reset
BLD='\e[1m'   # Bold
DIM='\e[2m'   # Dim
UND='\e[4m'   # Underline
INV='\e[7m'   # Invert
HID='\e[8m'   # Hidden
BLK='\e[30m'  # Black
RED='\e[31m'  # Red
GRN='\e[32m'  # Green
YLW='\e[33m'  # Yellow
BLU='\e[34m'  # Blue
MGN='\e[35m'  # Magenta
CYN='\e[36m'  # Cyan
WHT='\e[37m'  # White
BBLK='\e[90m' # Bright Black (Gray)
BRED='\e[91m' # Bright Red
BGRN='\e[92m' # Bright Green
BYLW='\e[93m' # Bright Yellow
BBLU='\e[94m' # Bright Blue
BMGN='\e[95m' # Bright Magenta
BCYN='\e[96m' # Bright Cyan
BWHT='\e[97m' # Bright White
#──────────── Background Colors ──────────
BG_BLK='\e[40m'  # Background Black
BG_RED='\e[41m'  # Background Red
BG_GRN='\e[42m'  # Background Green
BG_YLW='\e[43m'  # Background Yellow
BG_BLU='\e[44m'  # Background Blue
BG_MGN='\e[45m'  # Background Magenta
BG_CYN='\e[46m'  # Background Cyan
BG_WHT='\e[47m'  # Background White
BG_BBLK='\e[100m' # Background Bright Black
BG_BRED='\e[101m' # Background Bright Red
BG_BGRN='\e[102m' # Background Bright Green
BG_BYLW='\e[103m' # Background Bright Yellow
BG_BBLU='\e[104m' # Background Bright Blue
BG_BMGN='\e[105m' # Background Bright Magenta
BG_BCYN='\e[106m' # Background Bright Cyan
BG_BWHT='\e[107m' # Background Bright White
#─────────────────────────────────────────

#–– Helpers
has() { command -v "$1" &>/dev/null; }

# Fully safe optimal privelege tool
suexec="$(command -v sudo-rs 2>/dev/null || command -v sudo 2>/dev/null || command -v doas 2>/dev/null || :)"
[[ "${suexec:-}" == */sudo-rs || "${suexec:-}" == */sudo ]] && "$suexec" -v || :
suexec="${suexec:-sudo}"
if ! command -v "$suexec" &>/dev/null; then
  echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
  exit 1
fi
