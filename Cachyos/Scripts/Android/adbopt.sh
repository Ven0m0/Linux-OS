#!/usr/bin/env bash
export LC_ALL=C LANG=C

printf '%s\n' "Optimizing"

adb shell cmd shortcut reset-all-throttling
adb shell pm trim-caches 999999M
adb shell sm fstrim
