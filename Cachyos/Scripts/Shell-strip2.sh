#!/usr/bin/env bash
LC_ALL LANG=C.UTF-8
INPUT="${1:?Usage: $0 <script.sh>}"

pp_strip_comments(){ sed '/^[[:space:]]*#.*$/d'; }
pp_strip_copyright(){ awk '/^#/ {if(!p){ next }} { p=1; print }'; }
pp_strip_separators(){ awk '/^#\s*-{5,}/ { next } { print }'; }

{
  pp_strip_separators <"$INPUT" \
  | pp_strip_copyright \
  | pp_strip_comments \
  | shfmt -mn -ln bash -fn -ci -kp \
  | shellharden
} >"${INPUT%.sh}.optimized.sh"

shellcheck "${INPUT%.sh}.optimized.sh"
echo "Optimized script saved as ${INPUT%.sh}.optimized.sh"


