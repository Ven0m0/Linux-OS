#!/bin/bash
set -e

# Recreated lint-format.sh
CHECK_MODE=0
if [[ "$1" == "-c" ]]; then
  CHECK_MODE=1
fi

FD="${FD:-fd}"
if ! command -v "$FD" >/dev/null 2>&1; then
  FD="fdfind"
fi

echo "Using FD tool: $FD"

if [[ "$CHECK_MODE" -eq 1 ]]; then
  echo "Running in check mode..."
  # ShellCheck
  if command -v "$FD" >/dev/null 2>&1 && command -v shellcheck >/dev/null 2>&1; then
      "$FD" -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=error
  fi
  # shfmt
  if command -v "$FD" >/dev/null 2>&1 && command -v shfmt >/dev/null 2>&1; then
      "$FD" -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -i 2 -ci -sr -l
  fi

  # Ruff
  if command -v ruff >/dev/null 2>&1; then
      ruff check .
      ruff format --check .
  fi

else
  echo "Running in format mode..."
  # ShellCheck
  if command -v "$FD" >/dev/null 2>&1 && command -v shellcheck >/dev/null 2>&1; then
      "$FD" -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=style || true
  fi
  # shfmt format
  if command -v "$FD" >/dev/null 2>&1 && command -v shfmt >/dev/null 2>&1; then
      "$FD" -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -w -i 2 -ci -sr || true
  fi

  # Ruff format
  if command -v ruff >/dev/null 2>&1; then
      ruff check --fix . || true
      ruff format . || true
  fi
fi

echo "Lint and format complete."
