#!/usr/bin/env bash
# Compatibility wrapper (deprecated): use android-toolkit.sh clean
set -euo pipefail
IFS=$'\n\t'
exec "$(dirname "$0")/android-toolkit.sh" clean "$@"
