#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
# Convenience wrapper for account_scanner.py with env var support
# Usage: ./scan.sh username [--mode MODE] [options...]
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" || exit 1
SCRIPT_DIR="$(pwd -P)"
readonly SCRIPT_DIR
readonly SCANNER="${SCRIPT_DIR}/account_scanner.py"
# Load credentials from env or config file
readonly CREDS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/account_scanner/credentials"
if [[ -f $CREDS_FILE ]]; then
  # shellcheck source=/dev/null
  source "$CREDS_FILE"
fi
# Build args array
args=()
[[ ${PERSPECTIVE_API_KEY:-} ]] && args+=(--perspective-api-key "$PERSPECTIVE_API_KEY")
[[ ${REDDIT_CLIENT_ID:-} ]] && args+=(--client-id "$REDDIT_CLIENT_ID")
[[ ${REDDIT_CLIENT_SECRET:-} ]] && args+=(--client-secret "$REDDIT_CLIENT_SECRET")
[[ ${REDDIT_USER_AGENT:-} ]] && args+=(--user-agent "$REDDIT_USER_AGENT")
# Check Python
command -v python3 &> /dev/null || {
  printf 'python3 not found\n' >&2
  exit 1
}
# Check scanner exists
[[ -f $SCANNER ]] || {
  printf 'Scanner not found: %s\n' "$SCANNER" >&2
  exit 1
}
# Run with merged args
exec python3 "$SCANNER" "${args[@]}" "$@"
