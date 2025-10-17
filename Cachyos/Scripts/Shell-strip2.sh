#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C LANG=C SHELL=bash

readonly INPUT="${1:?Usage: $0 <script.sh>}"
readonly OUT="${INPUT%.sh}.optimized.sh"

# Detect tools once
readonly HAS_SD=$(command -v sd &>/dev/null && echo 1 || echo 0)
readonly HAS_FD=$(command -v fd &>/dev/null && echo 1 || echo 0)

pp_strip_comments(){ sed '/^[[:space:]]*#.*$/d'; }
pp_strip_copyright(){ awk '/^#/{if(!p)next}{p=1;print}'; }
pp_strip_separators(){ sed '/^#[[:space:]]*-\{5,\}/d'; }
pp_normalize_redirects(){
  [[ $HAS_SD -eq 1 ]] && sd '&>/dev/null' '&>/dev/null' || sed 's|&>/dev/null|>/dev/null 2>\&1|g'
}
dofunc(){
  [[ $HAS_SD -eq 1 ]] && sd '\(\) \{' '(){' "$1" || sed -i 's/() {/(){/g' "$1"
}
dotrue(){
  [[ $HAS_SD -eq 1 ]] && sd '\|\| true' '|| :' "$1" || sed -i 's/|| true/|| :/g' "$1"
}
donull(){
  [[ $HAS_SD -eq 1 ]] && sd '&>/dev/null' '&>/dev/null' "$1" || sed -i 's|&>/dev/null|>/dev/null 2>\&1|g' "$1"
}
search(){
  local -n cmd=$1
  [[ $HAS_FD -eq 1 ]] && fd -e sh -e bash -x "${cmd[@]}" {} || find . -type f \( -name '*.sh' -o -name '*.bash' \) -exec "${cmd[@]}" {} +
}
dofmt(){ shfmt -ln bash -i 2 -bn -s -w -- "$1" || :; }
docheck(){ shellcheck -a -x -s bash -P SCRIPTDIR -f diff -- "$1" | patch -Nlp1 &>/dev/null || :; }
doharden(){ shellharden --replace -- "$1" &>/dev/null || :; }

{
  pp_strip_separators <"$INPUT" |
  pp_strip_copyright |
  pp_strip_comments |
  pp_normalize_redirects |
  shfmt -mn -ln bash -fn -ci -kp |
  shellharden
} >"$OUT"

shellcheck "$OUT" && echo "Saved: $OUT" || echo "Warning: shellcheck failed"
