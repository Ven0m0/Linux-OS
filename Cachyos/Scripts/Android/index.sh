#!/data/data/com.termux/files/usr/bin/bash
# Usage: ./touch_hidden_files.sh [path]
# If no path given, uses current directory

BASE_DIR="${1:-.}"

find "$BASE_DIR" -type d -readable | while IFS= read -r dir; do
  for f in .metadata_never_index .noindex .trackerignore; do
    touch "$dir/$f"
  done
done
