#!/bin/bash
set -eo pipefail

CHECK_ONLY=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--check) CHECK_ONLY=1 ;;
        *) echo "Unknown parameter passed: $1"; false ;;
    esac
    shift
done

FD=${FD:-fdfind}

if ! command -v $FD >/dev/null 2>&1; then
  if command -v fd >/dev/null 2>&1; then
    FD=fd
  else
    FD="find . -type f -name '*.sh'"
  fi
fi

# Find all shell scripts excluding the WIP directory
if [[ "$FD" == "find"* ]]; then
    SCRIPTS=$( eval "$FD" | grep -v 'Cachyos/Scripts/WIP' || true )
else
    SCRIPTS=$( $FD -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' || true )
fi

if [ -z "$SCRIPTS" ]; then
    echo "No shell scripts found to lint."
else
    if [ $CHECK_ONLY -eq 1 ]; then
        if command -v shellcheck >/dev/null 2>&1; then
            echo "Running shellcheck in check mode..."
            echo "$SCRIPTS" | xargs shellcheck --severity=error
        fi

        if command -v shfmt >/dev/null 2>&1; then
            echo "Running shfmt in check mode..."
            echo "$SCRIPTS" | xargs shfmt -i 2 -ci -sr -l
        fi
    else
        if command -v shellcheck >/dev/null 2>&1; then
            echo "Running shellcheck..."
            echo "$SCRIPTS" | xargs shellcheck --severity=style || true
        fi

        if command -v shfmt >/dev/null 2>&1; then
            echo "Running shfmt to format..."
            echo "$SCRIPTS" | xargs shfmt -i 2 -ci -sr -w
        fi
    fi
fi
echo "Lint and format complete."
