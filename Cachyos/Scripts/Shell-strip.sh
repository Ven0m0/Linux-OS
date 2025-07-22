#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

#export SHELLCHECK_OPTS="--enable=quote-safe-variables --exclude=SC2054"
FILE="${1:?Usage: $0 <script.sh>}"
OUTPUT="${FILE%.sh}.optimized.sh"
cp "$FILE" "$FILE.bak"

# 1. Run shellharden to auto-quote variables safely (in-place)
#    --transform rewrites the script, keeping a backup as .bak if we specify --replace
shellharden --transform --replace "$FILE"

# 2. Apply ShellCheck's suggested diffs (for issues it can auto-fix)
shellcheck -s bash --exclude=SC2054 --format=diff "$FILE" | patch "$FILE" || true

# Format and minify the script
shfmt -ln=bash -i=2 "$FILE" > "$OUTPUT"

echo "Auto-fixed script saved to: $FILE"
echo "Backup of original saved as: $FILE.bak"
