#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
# Demo script showing all scanner modes
readonly TEST_USER="${1:-spez}"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" || exit 1
SCRIPT_DIR="$(pwd -P)"
readonly SCANNER="${SCRIPT_DIR}/account_scanner.py"

printf '\n=== Account Scanner Demo ===\n\n'
check_deps() {
  local -a missing=()
  command -v python3 &> /dev/null || missing+=(python3)
  command -v sherlock &> /dev/null || missing+=(sherlock)
  python3 -c "import praw" 2> /dev/null || missing+=(python-praw)
  python3 -c "import httpx" 2> /dev/null || missing+=(python-httpx)
  python3 -c "import orjson" 2> /dev/null || missing+=(python-orjson)
  python3 -c "import uvloop" 2> /dev/null || missing+=(python-uvloop)
  if ((${#missing[@]} > 0)); then
    printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
    printf 'Install: pacman -S python-praw python-httpx python-orjson python-uvloop sherlock-git\n' >&2
    return 1
  fi
}
printf 'Checking dependencies...\n'
check_deps || exit 1
printf 'Using test username: %s\n\n' "$TEST_USER"
# Demo 1: Sherlock
printf '\n--- Demo 1: Sherlock Mode ---\n'
printf 'Press Enter to run (or Ctrl+C to skip)...'
read -r
python3 "$SCANNER" "$TEST_USER" --mode sherlock \
  --output-sherlock "demo_sherlock_${TEST_USER}.json" \
  --sherlock-timeout 30 --verbose
# Demo 2: Reddit
printf '\n\n--- Demo 2: Reddit Mode ---\n'
printf 'Skip this demo? (Y/n): '
read -r skip
if [[ ! $skip =~ ^[Nn] ]]; then
  printf 'Skipped.\n'
else
  if [[ -f $HOME/.config/account_scanner/credentials ]]; then
    source "$HOME/.config/account_scanner/credentials"
    if [[ -n ${PERSPECTIVE_API_KEY:-} ]]; then
      python3 "$SCANNER" "$TEST_USER" --mode reddit \
        --perspective-api-key "$PERSPECTIVE_API_KEY" \
        --client-id "$REDDIT_CLIENT_ID" \
        --client-secret "$REDDIT_CLIENT_SECRET" \
        --user-agent "${REDDIT_USER_AGENT:-AccountScanner/1.0}" \
        --comments 20 --posts 5 --output-reddit "demo_reddit_${TEST_USER}.csv"
    else
      printf 'Credentials incomplete.\n'
    fi
  else
    printf 'No credentials file.\n'
  fi
fi
