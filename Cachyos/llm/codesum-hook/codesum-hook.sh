#!/usr/bin/env bash
# shellcheck enable=all shell=bash
set -euo pipefail
IFS=$'\n\t'

# Claude Code hook: Generate optimized code summary
# Usage: codesum-hook.sh [project_dir]

PROJECT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODESUM="${SCRIPT_DIR}/codesum.py"

# Verify codesum.py exists
[[ -x "$CODESUM" ]] || { echo "Error: $CODESUM not found or not executable" >&2; exit 1; }

# Run in batch mode, output summary path
cd "$PROJECT_DIR" || exit 1
python3 "$CODESUM" --all 2>/dev/null

# Output the summary file path for Claude Code to read
SUMMARY_FILE="${PROJECT_DIR}/.summary_files/code_summary.md"
if [[ -f "$SUMMARY_FILE" ]]; then
  cat "$SUMMARY_FILE"
else
  echo "Error: Summary generation failed" >&2
  exit 1
fi
