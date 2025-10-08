#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C 
LANG=C

if ! command -v adb &>/dev/null; then
  printf '%s\n' "adb not found" >&2
  exit 1
fi

adb shell sync


adb shell device_config put activity_manager_native_boot use_freezer true
