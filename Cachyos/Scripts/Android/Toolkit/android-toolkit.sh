#!/usr/bin/env bash
# Wrapper for the unified android-optimize.sh script
# This ensures backward compatibility while centralizing logic.

set -euo pipefail

# Resolve the directory of the script
DIR="${BASH_SOURCE[0]%/*}"
# Navigate up one level to find android-optimize.sh if this is in Toolkit/
ROOT_DIR="$(cd "$DIR/.." && pwd)"

SCRIPT="$ROOT_DIR/android-optimize.sh"

if [[ -f $SCRIPT ]]; then
  exec "$SCRIPT" "$@"
else
  echo "Error: android-optimize.sh not found at $SCRIPT"
  exit 1
fi
