#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# (No -x debug mode in normal use)

INPUT="${1:?Usage: $0 <script.sh>}"
OUTPUT="${INPUT%.sh}.optimized.sh"

# Format and minify the script
shfmt -ln=bash -i=2 "$INPUT" > "$OUTPUT"

# Lint the result explicitly as Bash
shellcheck -s bash --exclude=SC2054 "$OUTPUT"

echo "Optimized script saved as $OUTPUT"
