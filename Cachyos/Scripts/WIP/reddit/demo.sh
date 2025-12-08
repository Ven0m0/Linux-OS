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
check_deps() {
  local -a missing=()
  command -v python3 &> /dev/null || missing+=(python3)
  command -v sherlock &> /dev/null || missing+=(sherlock)
  python3 -c "import praw" 2> /dev/null || missing+=(python-praw)
  python3 -c "import pandas" 2> /dev/null || missing+=(python-pandas)
  python3 -c "import httpx" 2> /dev/null || missing+=(python-httpx)
  if ((${#missing[@]} > 0)); then
    printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
    printf '\nInstall on Arch:\n' >&2
    printf '  pacman -S python-praw python-pandas python-httpx\n' >&2
    printf '  yay -S sherlock-git\n' >&2
    return 1
  fi
}
printf 'Checking dependencies...\n'
check_deps || exit 1
printf 'Using test username: %s\n\n' "$TEST_USER"
# Demo 1: Sherlock only (no API keys needed)
printf '\n--- Demo 1: Sherlock Mode (Platform Discovery) ---\n'
printf 'Command: ./account_scanner.py %s --mode sherlock --verbose\n\n' "$TEST_USER"
printf 'This discovers username presence across 400+ platforms.\n'
printf 'No Reddit API credentials required.\n'
printf 'Press Enter to run (or Ctrl+C to skip)...'
read -r
python3 "$SCANNER" "$TEST_USER" \
  --mode sherlock \
  --output-sherlock "demo_sherlock_${TEST_USER}.json" \
  --sherlock-timeout 30 \
  --verbose
# Demo 2: Reddit mode (requires creds)
printf '\n\n--- Demo 2: Reddit Mode (Toxicity Analysis) ---\n'
printf 'Command: ./account_scanner.py %s --mode reddit [credentials...]\n\n' "$TEST_USER"
printf 'This analyzes Reddit comments/posts for toxic content.\n'
printf 'Requires Reddit API + Perspective API credentials.\n'
printf 'Skip this demo? (Y/n): '
read -r skip
if [[ ! $skip =~ ^[Nn] ]]; then
  printf 'Skipped (requires API credentials)\n'
else
  # Check if credentials exist
  if [[ -f $HOME/.config/account_scanner/credentials ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/account_scanner/credentials"
    if [[ -n ${PERSPECTIVE_API_KEY:-} && -n ${REDDIT_CLIENT_ID:-} ]]; then
      python3 "$SCANNER" "$TEST_USER" \
        --mode reddit \
        --perspective-api-key "$PERSPECTIVE_API_KEY" \
        --client-id "$REDDIT_CLIENT_ID" \
        --client-secret "$REDDIT_CLIENT_SECRET" \
        --user-agent "${REDDIT_USER_AGENT:-AccountScanner/1.0}" \
        --comments 20 \
        --posts 5 \
        --toxicity-threshold 0.7 \
        --output-reddit "demo_reddit_${TEST_USER}.csv"
    else
      printf 'Credentials incomplete in ~/.config/account_scanner/credentials\n'
    fi
  else
    printf 'No credentials file. See credentials.example\n'
  fi
fi

# Demo 3: Both modes
printf '\n\n--- Demo 3: Both Modes (Concurrent Execution) ---\n'
printf 'Command: ./account_scanner.py %s --mode both [credentials...]\n\n' "$TEST_USER"
printf 'This runs Sherlock + Reddit analysis concurrently.\n'
printf 'Skip this demo? (Y/n): '
read -r skip
if [[ ! $skip =~ ^[Nn] ]]; then
  printf 'Skipped (requires API credentials)\n'
else
  if [[ -f $HOME/.config/account_scanner/credentials ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.config/account_scanner/credentials"
    if [[ -n ${PERSPECTIVE_API_KEY:-} && -n ${REDDIT_CLIENT_ID:-} ]]; then
      printf '\nRunning both scanners concurrently...\n\n'
      python3 "$SCANNER" "$TEST_USER" \
        --mode both \
        --perspective-api-key "$PERSPECTIVE_API_KEY" \
        --client-id "$REDDIT_CLIENT_ID" \
        --client-secret "$REDDIT_CLIENT_SECRET" \
        --user-agent "${REDDIT_USER_AGENT:-AccountScanner/1.0}" \
        --comments 20 \
        --posts 5 \
        --output-reddit "demo_both_reddit_${TEST_USER}.csv" \
        --output-sherlock "demo_both_sherlock_${TEST_USER}.json" \
        --verbose
    fi
  fi
fi
printf '\n\n=== Demo Complete ===\n'
printf '\nGenerated files:\n'
ls -lh demo_* 2> /dev/null || printf 'No demo files (credentials may be missing)\n'
printf '\nTry these commands:\n'
printf '  # Quick username check (no API keys)\n'
printf '  ./account_scanner.py USERNAME --mode sherlock\n\n'
printf '  # Full analysis (with credentials)\n'
printf '  ./scan.sh USERNAME --mode both\n\n'
