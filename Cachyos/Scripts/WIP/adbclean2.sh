#!/usr/bin/env bash
set -euo pipefail

echo "=== Android 15 Junk Cleanup ==="

# Helpers
clean_storage() {
  local folder=$1
  echo "→ Cleaning junk in $folder"
  find "$folder" -type f \( \
    -iname "*.tmp" -o -iname "*.temp" -o -iname "*.crdownload" \
    -o -iname "*.partial" -o -iname "*.log" -o -iname "*.cache" \
    -o -iname "*.thumb" \
    \) -exec rm -f {} + 2> /dev/null || :
}

remove_empty_dirs() {
  echo "→ Removing empty directories under /sdcard"
  find /sdcard/ -type d -empty -delete 2> /dev/null || :
}

clear_caches_with_shizuku() {
  echo "→ Clearing app caches via Shizuku"
  for pkg in "${pkgs[@]}"; do
    echo "   • $pkg"
    if "$is_pc"; then
      adb shell "shizuku pm clear $pkg" > /dev/null 2>&1 || echo "     ✗ failed"
    else
      shizuku pm clear "$pkg" > /dev/null 2>&1 || echo "     ✗ failed"
    fi
  done
}

recompile_packages() {
  echo "→ Fallback: forcing recompilation (may free cache) via cmd package compile -r"
  for pkg in "${pkgs[@]}"; do
    echo "   • $pkg"
    if "$is_pc"; then
      adb shell "cmd package compile -r $pkg" > /dev/null 2>&1 || echo "     ✗ failed"
    else
      cmd package compile -r "$pkg" > /dev/null 2>&1 || echo "     ✗ failed"
    fi
  done
}

# Detect environment
is_pc=false
if command -v adb &> /dev/null; then
  if adb get-state &> /dev/null; then
    is_pc=true
    echo "Detected: running on PC → controlling device via adb"
  fi
fi

# Gather package list (third‑party only)
echo "Gathering installed user apps…"
if "$is_pc"; then
  mapfile -t pkgs < <(adb shell pm list packages -3 | cut -d':' -f2)
else
  mapfile -t pkgs < <(pm list packages -3 | cut -d':' -f2)
fi

# Attempt cache clear
if "$is_pc"; then
  # Check if Shizuku is installed on device
  if adb shell command -v shizuku &> /dev/null; then
    clear_caches_with_shizuku
  else
    recompile_packages
  fi
else
  # On‑device
  if command -v shizuku &> /dev/null; then
    clear_caches_with_shizuku
  else
    recompile_packages
  fi
fi

# Clean storage areas
for dir in /sdcard/Download /sdcard/DCIM /sdcard/Pictures /sdcard/Movies /sdcard/Music; do
  clean_storage "$dir"
done

# Remove empties
remove_empty_dirs

echo "=== Cleanup complete! ==="
