#!/usr/bin/env bash
# Compatibility wrapper (deprecated): use android-toolkit.sh device-config
set -euo pipefail
IFS=$'\n\t'
sub="${1:-apply}"
shift || :
exec "${"$0"%/*}/android-toolkit.sh" device-config "$sub" "$@"
