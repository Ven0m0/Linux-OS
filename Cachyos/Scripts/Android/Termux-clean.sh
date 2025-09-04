#!/bin/sh
LC_ALL=C LANG=C

echo "🔄 Clearing per-app cache (third-party apps)..."
adb shell pm list packages -3 | cut -d: -f2 \
  | xargs -n1 -I{} adb shell pm clear --cache-only {}

echo "🔄 Clearing per-app cache (system apps)..."
adb shell pm list packages -s | cut -d: -f2 \
  | xargs -n1 -I{} adb shell pm clear --cache-only {}

echo "🧹 Trimming system-wide app caches..."
adb shell pm trim-caches 128G

echo "🗑️ Deleting log, backup, and temp files from /sdcard..."
adb shell 'find /sdcard -type f \( \
    -iname "*.log" -o \
    -iname "*.bak" -o \
    -iname "*.old" -o \
    -iname "*.tmp" -o \
    -iname "*~" -o \
    -iname "*.json.bak" \
  \) -delete'

# Replace `/sdcard` with all external volumes
for path in $(adb shell ls /storage | grep -v emulated); do
  adb shell "find /storage/$path -type f \( ... \) -delete"
done

# echo "🧠 Clearing ART/JIT profiles (third-party apps)..."
# adb shell pm list packages -3 | cut -d: -f2 \
#   | xargs -n1 -I{} adb shell pm art clear-app-profiles {}

echo "🧼 Clearing all logcat buffers..."
adb logcat -b all -c

echo "✅ Finished. Cache, log files, and junk cleaned up."
