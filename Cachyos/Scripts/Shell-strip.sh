#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
# (No -x debug mode in normal use)

INPUT="${1:?Usage: $0 <script.sh>}"

# (Optional) preserve the original shebang if present
# If the script’s first line is "#!", store it in SHEBANG
read -r FIRST_LINE < "$INPUT"
if [[ $FIRST_LINE == \#!* ]]; then
  SHEBANG="$FIRST_LINE"
  # remove shebang from the stream so shfmt/shellharden don't duplicate it
  tail -n +2 "$INPUT" \
    | shfmt -mn -ln bash -fn -ci -kp \
    | shellharden --transform \
    > "${INPUT%.sh}.optimized.sh"
  # Prepend the shebang to the output file
  sed -i "1s;^;${SHEBANG}\n;" "${INPUT%.sh}.optimized.sh"
else
  # No shebang: just transform normally and add a default shebang
  { printf '%s\n' '#!/bin/bash'
    shfmt -mn -ln bash -fn -ci -kp < "$INPUT" \
    | shellharden --transform
  } > "${INPUT%.sh}.optimized.sh"
fi

# Lint the result explicitly as bash (avoiding SC2148 warnings)
shellcheck -s bash "${INPUT%.sh}.optimized.sh"

echo "Optimized script saved as ${INPUT%.sh}.optimized.sh"
