#!/bin/bash
set -euo pipefail
set -x

INPUT="${1:?Usage: $0 <script.sh>}"

# Strip out unneeded stuff
pp_strip_separators() {
    awk '/^#\s*-{5,}/ { next; } { print }'
}

pp_strip_copyright() {
    awk '/^#/ { if(!p){ next } } { p=1; print }'
}

pp_strip_comments() {
    sed '/^[[:space:]]*#.*$/d'
}

# Process the script
cat "$INPUT" \
  | pp_strip_separators \
  | pp_strip_copyright \
  | pp_strip_comments \
  | shfmt -mn -ln bash -fn -ci -kp \
  | shellharden \
  > "${INPUT%.sh}.optimized.sh"

# Lint the result
shellcheck "${INPUT%.sh}.optimized.sh"
echo "Optimized script saved as ${INPUT%.sh}.optimized.sh"
