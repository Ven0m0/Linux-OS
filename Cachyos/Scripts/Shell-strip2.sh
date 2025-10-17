#!/usr/bin/env bash
LC_ALL=C LANG=C
SHELL=bash
INPUT="${1:?Usage: $0 <script.sh>}"

pp_strip_comments(){ sed '/^[[:space:]]*#.*$/d'; }
pp_strip_copyright(){ awk '/^#/ {if(!p){ next }} { p=1; print }'; }
pp_strip_separators(){ awk '/^#\s*-{5,}/ { next } { print }'; }

dofunc(){
  if command -v sd &>/dev/null; then
    sd '\(\) \{' '(){' "$1"
  else
    sed -i 's/() {/(){/g' "$1"
  fi
}
dotrue(){
  if command -v sd &>/dev/null; then
    sd '\|\| true' '|| :'
  else
    sed -i 's/|| true/|| :/g'
  fi
}

search(){
  if command -v fd &>/dev/null; then
    fd '\.(sh|bash)$' -x "$1" {}
  else
    find . -name '*.sh' -exec "$1" {} +
  fi
}

dofmt(){ shfmt -ln=bash -i 2 -bn -s -w -- "$1"; }

docheck(){ shellcheck -a -x -s bash -P "SCRIPTDIR" -f diff -- "$1" | patch -Nlp1; }

doharden(){ shellharden --replace -- "$1"; }

{
  pp_strip_separators <"$INPUT" \
  | pp_strip_copyright \
  | pp_strip_comments \
  | shfmt -mn -ln bash -fn -ci -kp \
  | shellharden
} >"${INPUT%.sh}.optimized.sh"

shellcheck "${INPUT%.sh}.optimized.sh"
echo "Optimized script saved as ${INPUT%.sh}.optimized.sh"


