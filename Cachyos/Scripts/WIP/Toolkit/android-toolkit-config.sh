#!/usr/bin/env bash
# Compatibility wrapper (deprecated): use android-toolkit.sh optimize
set -euo pipefail
IFS=$'\n\t'
# Map legacy flags to new
profile=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -p | --profile)
    profile="$2"
    shift 2
    ;;
  -c | --category)
    args+=("$2")
    shift 2
    ;;
  -d | --device | -y | --yes | -v | --verbose | -i | --interactive)
    args+=("$1")
    shift
    ;;
  *)
    args+=("$1")
    shift
    ;;
  esac
done
if [[ -n "$profile" ]]; then
  exec "$(dirname "$0")/android-toolkit.sh" optimize --profile "$profile" "${args[@]}"
else exec "$(dirname "$0")/android-toolkit.sh" optimize "${args[@]}"; fi
