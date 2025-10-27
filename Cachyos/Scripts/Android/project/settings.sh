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
adb shell settings put global activity_manager_constants max_cached_processes=32
adb shell settings put global anr_show_background false
adb shell settings put global sys.use_fifo_ui 1
adb shell cmd wifi set-verbose-logging disabled
adb shell cmd wifi set-scan-always-available disabled
