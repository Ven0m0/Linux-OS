#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar; LC_ALL=C
# inifmt: Compact INI formatter
# Usage: inifmt [file] (reads stdin if no file)
awk '
  # Pass comments (start with ; or #) and empty lines unmodified
  /^[ \t]*([;#]|$)/ { print; next }
  # Format sections: trim whitespace around [Section]
  /^[ \t]*\[/ {
    gsub(/^[ \t]+|[ \t]+$/, "")
    print
    next
  }
  # Format Key=Value: ensure "key = value" spacing
  match($0, /=/) {
    k = substr($0, 1, RSTART - 1)
    v = substr($0, RSTART + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", k)
    gsub(/^[ \t]+|[ \t]+$/, "", v)
    printf "%s = %s\n", k, v
  }
' "${1:-/dev/stdin}"
