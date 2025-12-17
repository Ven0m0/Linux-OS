#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCANNER="${SCRIPT_DIR}/account_scanner.py"
readonly CREDS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/account_scanner/credentials"
[[ -f $SCANNER ]] || { printf 'Scanner not found: %s\n' "$SCANNER" >&2; exit 1; }
[[ -f $CREDS_FILE ]] && source "$CREDS_FILE"
args=()
[[ ${PERSPECTIVE_API_KEY:-} ]] && args+=(--perspective-api-key "$PERSPECTIVE_API_KEY")
[[ ${REDDIT_CLIENT_ID:-} ]] && args+=(--client-id "$REDDIT_CLIENT_ID")
[[ ${REDDIT_CLIENT_SECRET:-} ]] && args+=(--client-secret "$REDDIT_CLIENT_SECRET")
[[ ${REDDIT_USER_AGENT:-} ]] && args+=(--user-agent "$REDDIT_USER_AGENT")
command -v python3 &>/dev/null || { printf 'python3 not found\n' >&2; exit 1; }
exec python3 "$SCANNER" "${args[@]}" "$@"
