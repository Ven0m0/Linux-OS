#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C LANG=C SHELL=bash

usage(){
  cat <<EOF
Usage: ${0##*/} <script.sh> [--batch]
Options:
  --batch     Run in-place replacements across repo (uses fd/find)
  -h, --help  Show help
EOF
}

readonly INPUT="${1:?Usage: $0 <script.sh>}"
readonly OUT="${INPUT%.sh}.optimized.sh"
readonly HAS_SD=$(command -v sd >/dev/null 2>&1 && echo 1 || echo 0)
readonly HAS_FD=$(command -v fd >/dev/null 2>&1 && echo 1 || echo 0)
readonly HAS_SHFMT=$(command -v shfmt >/dev/null 2>&1 && echo 1 || echo 0)
readonly HAS_SHELLCHECK=$(command -v shellcheck >/dev/null 2>&1 && echo 1 || echo 0)
readonly HAS_SHELLHARDEN=$(command -v shellharden >/dev/null 2>&1 && echo 1 || echo 0)
pp_strip_comments(){ sed '/^[[:space:]]*#.*$/d'; }
pp_strip_copyright(){ awk '/^#/{if(!p)next}{p=1;print}'; }
pp_strip_separators(){ sed '/^#[[:space:]]*-\{5,\}/d'; }

pp_normalize_redirects(){ [[ $HAS_SD -eq 1 ]] && sd '&>/dev/null' '&>/dev/null' || sed 's|&>/dev/null|>/dev/null 2>\&1|g'; }
dofunc(){ [[ $HAS_SD -eq 1 ]] && sd '\(\) \{' '(){' "$1" || sed -i 's/() {/(){/g' "$1"; }
dotrue(){ [[ $HAS_SD -eq 1 ]] && sd '\|\| true' '|| :' "$1" || sed -i 's/|| true/|| :/g' "$1"; }

# find shell files (NUL-separated)
files_in_repo(){
  local -n out=$1
  out=()
  if [[ $HAS_FD -eq 1 ]]; then
    mapfile -d '' -t out < <(fd -e sh -e bash -0 . 2>/dev/null)
  else
    mapfile -d '' -t out < <(find . -type f \( -name '*.sh' -o -name '*.bash' \) -print0)
  fi
}
# batch in-place: one perl invocation per file, then optional shfmt
batch_replace(){
  local files f
  files_in_repo files
  for f in "${files[@]}"; do
    perl -i -pe 's/\(\) \{/(){/g; s/\|\| true/|| :/g; s/&>\/dev\/null/>\/dev\/null 2>&1/g' "$f"
    [[ $HAS_SHFMT -eq 1 ]] && shfmt -ln bash -i 2 -bn -s -w -- "$f" >/dev/null 2>&1 || true
  done
}
# arg dispatch (second arg controls mode)
case "${2:-}" in
  --batch) batch_replace; printf 'Batch replacements complete\n'; exit 0 ;;
  -h|--help) usage; exit 0 ;;
  -V|--ver) printf '%s\n' "$VERSION"; exit 0 ;;
esac
# single-file pipeline: strip headers/comments, normalize, format, harden
{
  pp_strip_separators <"$INPUT" \
  | pp_strip_copyright \
  | pp_strip_comments \
  | pp_normalize_redirects \
  | dofunc \
  | dotrue \
  | { [[ $HAS_SHFMT -eq 1 ]] && shfmt -mn -ln bash -fn -ci -kp || cat; } \
  | { [[ $HAS_SHELLHARDEN -eq 1 ]] && shellharden || cat; }
} >"$OUT"
if [[ $HAS_SHELLCHECK -eq 1 ]]; then
  shellcheck "$OUT" >/dev/null 2>&1 && printf 'Saved: %s\n' "$OUT" || printf 'Warning: shellcheck failed for %s\n' "$OUT"
else
  printf 'Saved: %s (shellcheck not installed)\n' "$OUT"
fi
