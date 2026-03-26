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

if [[ "$FD" == "find"* ]]; then
    if [ $CHECK_ONLY -eq 1 ]; then
        eval "$FD" | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=error
        eval "$FD" | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -i 2 -ci -sr -l
    else
        eval "$FD" | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=style || true
        eval "$FD" | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -i 2 -ci -sr -w
    fi
else
    if [ $CHECK_ONLY -eq 1 ]; then
        $FD -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=error
        $FD -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -i 2 -ci -sr -l
    else
        $FD -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shellcheck --severity=style || true
        $FD -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs -r shfmt -i 2 -ci -sr -w
    fi
fi

echo "Lint and format complete."
