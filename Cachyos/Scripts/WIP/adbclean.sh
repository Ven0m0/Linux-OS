#!/bin/bash

echo "Starting Android junk cleanup for non-rooted device..."

# Function to delete junk files in given directory
clean_dir() {
  local dir=$1
  echo "Cleaning junk files in $dir ..."
  find "$dir" -type f \( \
    -iname "*.tmp" -o -iname "*.temp" -o -iname "*.crdownload" -o -iname "*.partial" -o -iname "*.log" -o -iname "*.cache" -o -iname "*.thumb" \
  \) -exec rm -f {} +
}

# Detect if running inside adb shell or Termux (simple heuristic)
if [ "$(command -v adb)" ]; then
  # Running on PC: use adb shell for commands
  adb get-state >/dev/null 2>&1 || { echo "No device connected via adb."; exit 1; }
  echo "Running on PC with adb connection."

  # Delete junk files in storage areas
  for folder in /sdcard/Download /sdcard/DCIM /sdcard/Pictures /sdcard/Movies /sdcard/Music; do
    echo "Cleaning $folder ..."
    adb shell "find $folder -type f \( -iname '*.tmp' -o -iname '*.temp' -o -iname '*.crdownload' -o -iname '*.partial' -o -iname '*.log' -o -iname '*.cache' -o -iname '*.thumb' \) -delete"
  done

  # Remove empty directories
  echo "Removing empty directories in /sdcard..."
  adb shell "find /sdcard/ -type d -empty -delete"

  # Try clearing cache for user apps (limited, no root)
  echo "Attempting to clear app caches (limited)..."
  pkgs=$(adb shell pm list packages -3 | cut -d':' -f2)
  for pkg in $pkgs; do
    echo "Clearing cache for $pkg ..."
    adb shell cmd package compile -r "$pkg" 2>/dev/null
  done

else
  # Running on device shell (Termux or similar)
  echo "Running on device shell."

  # Make sure 'find' exists
  if ! command -v find >/dev/null 2>&1; then
    echo "'find' command not found. Cannot proceed."
    exit 1
  fi

  # Clean junk files
  for folder in /sdcard/Download /sdcard/DCIM /sdcard/Pictures /sdcard/Movies /sdcard/Music; do
    if [ -d "$folder" ]; then
      clean_dir "$folder"
    fi
  done

  # Remove empty directories
  echo "Removing empty directories in /sdcard..."
  find /sdcard/ -type d -empty -delete

  # Clear cache for user apps (Termux environment may not allow this, so skipping)
  echo "Skipping app cache clearing (needs adb or root)."
fi

echo "Android junk cleanup finished."
