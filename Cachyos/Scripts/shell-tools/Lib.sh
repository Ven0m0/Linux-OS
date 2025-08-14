#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
IFS=$'\n\t'
#──────────── Color & Effects ────────────
DEF='\033[0m'   # Default / Reset
BLD='\033[1m'   # Bold
DIM='\033[2m'   # Dim
UND='\033[4m'   # Underline
INV='\033[7m'   # Invert
HID='\033[8m'   # Hidden
BLK='\033[30m'  # Black
RED='\033[31m'  # Red
GRN='\033[32m'  # Green
YLW='\033[33m'  # Yellow
BLU='\033[34m'  # Blue
MGN='\033[35m'  # Magenta
CYN='\033[36m'  # Cyan
WHT='\033[37m'  # White
BBLK='\033[90m' # Bright Black (Gray)
BRED='\033[91m' # Bright Red
BGRN='\033[92m' # Bright Green
BYLW='\033[93m' # Bright Yellow
BBLU='\033[94m' # Bright Blue
BMGN='\033[95m' # Bright Magenta
BCYN='\033[96m' # Bright Cyan
BWHT='\033[97m' # Bright White
#──────────── Background Colors ──────────
BG_BLK='\033[40m'  # Background Black
BG_RED='\033[41m'  # Background Red
BG_GRN='\033[42m'  # Background Green
BG_YLW='\033[43m'  # Background Yellow
BG_BLU='\033[44m'  # Background Blue
BG_MGN='\033[45m'  # Background Magenta
BG_CYN='\033[46m'  # Background Cyan
BG_WHT='\033[47m'  # Background White
BG_BBLK='\033[100m' # Background Bright Black
BG_BRED='\033[101m' # Background Bright Red
BG_BGRN='\033[102m' # Background Bright Green
BG_BYLW='\033[103m' # Background Bright Yellow
BG_BBLU='\033[104m' # Background Bright Blue
BG_BMGN='\033[105m' # Background Bright Magenta
BG_BCYN='\033[106m' # Background Bright Cyan
BG_BWHT='\033[107m' # Background Bright White
#─────────────────────────────────────────
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"

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
