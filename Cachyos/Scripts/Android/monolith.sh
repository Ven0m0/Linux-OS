#!/usr/bin/env bash
LC_ALL=C LANG=C

# https://github.com/tytydraco/monolith
MODE="everything-profile"

echo ">>> PART 1"
adb shell cmd package compile -a -f -m "$MODE"

echo ">>> PART 2"
adb shell cmd package compile -a -f --compile-layouts

echo ">>> Cleaning up"
adb shell cmd package bg-dexopt-job

echo ">>> Done"
