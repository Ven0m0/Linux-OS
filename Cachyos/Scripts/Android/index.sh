#!/data/data/com.termux/files/usr/bin/bash

LC_ALL=C LANG=C
BASE_DIR="/storage/emulated/0"

find -O3 "$BASE_DIR" -type d -readable | while IFS= read -r dir; do
  for f in .metadata_never_index .noindex .trackerignore .nomedia; do
    touch "$dir/$f"
  done
done
