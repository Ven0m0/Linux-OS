#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
# Demo script showing all scanner modes
# Run: ./demo.sh [username]
readonly TEST_USER="${1:-spez}"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" || exit 1
SCRIPT_DIR="$(pwd -P)"
readonly SCRIPT_DIR
readonly SCANNER="${SCRIPT_DIR}/account_scanner.py"
printf '\n=== Account Scanner Demo ===\n\n'
# Check dependencies
check_deps(){
  local -a missing=()
  command -v python3 &>/dev/null || missing+=(python3)
  command -v sherlock &>/dev/null || missing+=(sherlock)
  python3 -c "import praw" 2>/dev/null || missing+=(python-praw)
  python3 -c "import httpx" 2>/dev/null || missing+=(python-httpx)
  if ((${#missing[@]} > 0)); then
    printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
    printf '\nInstall on Arch:\n' >&2
    printf '  pacman -S python-praw python-httpx\n' >&2
    printf '  yay -S sherlock-git\n' >&2
    return 1
  fi
}
printf 'Checking dependencies...\n'
check_deps || exit 1
# ... (rest of the script remains identical as args are compatible)
