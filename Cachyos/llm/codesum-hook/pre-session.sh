#!/usr/bin/env bash
# pre-session.sh: Async context generation for Claude Code.
set -euo pipefail

SCRIPT_DIR="${HOME}/.claude/hooks"
PROJECT_DIR="${PROJECT_DIR:-.}"

if [[ -f "${SCRIPT_DIR}/codesum.py" ]]; then
  # Run in background, suppress output
  python3 "${SCRIPT_DIR}/codesum.py" "$PROJECT_DIR" --hook &>/dev/null &
fi
