#!/usr/bin/env bash
# shellcheck enable=all shell=bash
# codesum-hook.sh: Generate code summary via unified python script.

set -euo pipefail
shopt -s nullglob globstar

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODESUM_PY="${SCRIPT_DIR}/codesum.py"

# --- Helpers ---
msg() { printf '%s\n' "$@"; }
die() { printf '%s\n' "$@" >&2; exit 1; }
has() { command -v -- "$1" &>/dev/null; }

# --- Main ---
[[ -x "$CODESUM_PY" ]] || die "Error: $CODESUM_PY not executable or found."
has python3 || die "Error: python3 not found."

PROJECT_DIR="${1:-.}"

# Execute in hook mode (silent generation, outputs path)
SUMMARY_PATH=$(python3 "$CODESUM_PY" "$PROJECT_DIR" --hook)

if [[ -f "$SUMMARY_PATH" ]]; then
  # Output content for consumption
  cat "$SUMMARY_PATH"
else
  die "Error: Summary generation failed at $PROJECT_DIR"
fi
