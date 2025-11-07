#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
LC_ALL=C LANG=C
readonly out="${1:-.}"
readonly jobs=$(nproc 2>/dev/null || echo 4)
readonly red=$'\e[31m' grn=$'\e[32m' ylw=$'\e[33m' rst=$'\e[0m'

check_deps(){
  local -a missing=()
  command -v bunx &>/dev/null || command -v npx &>/dev/null || missing+=(bun/node)
  command -v jaq &>/dev/null || command -v jq &>/dev/null || missing+=(jaq/jq)
  (( ${#missing[@]} > 0 )) && { printf "%s✗%s Missing: %s\n" "$red" "$rst" "${missing[*]}" >&2; exit 1; }
}

minify_css(){
  local f=$1 tmp len_in len_out
  len_in=$(wc -c <"$f")
  [[ $f =~ \.min\.css$ ]] && return 0
  tmp=$(mktemp)
  if command -v minhtml &>/dev/null; then
    minhtml --minify-css --allow-optimal-entities --allow-removing-spaces-between-attributes "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (minhtml failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  elif command -v bunx &>/dev/null; then
    bunx lightningcss --minify "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (lightningcss failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  else
    npx -y lightningcss --minify "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (lightningcss failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  fi
  len_out=$(wc -c <"$tmp")
  mv "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_css
export grn red rst

minify_html(){
  local f=$1 tmp len_in len_out
  len_in=$(wc -c <"$f")
  tmp=$(mktemp)
  if command -v minhtml &>/dev/null; then
    minhtml --minify-css --allow-optimal-entities --allow-removing-spaces-between-attributes "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (minhtml failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  elif command -v bunx &>/dev/null; then
    bunx @minify-html/node-cli "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (minify-html failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  else
    npx -y @minify-html/node-cli "$f" -o "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (minify-html failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  fi
  len_out=$(wc -c <"$tmp")
  mv "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_html

minify_json(){
  local f=$1 tmp len_in len_out
  len_in=$(wc -c <"$f")
  [[ $f =~ \.min\.json$|package(-lock)?\.json$ ]] && return 0
  tmp=$(mktemp)
  if command -v jaq &>/dev/null; then
    jaq -c . "$f" >"$tmp" 2>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (jaq failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  else
    jq -c . "$f" >"$tmp" 2>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (jq failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
  fi
  len_out=$(wc -c <"$tmp")
  mv "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_json

fmt_yaml(){
  local f=$1 tmp len_in len_out
  len_in=$(wc -c <"$f")
  tmp=$(mktemp)
  if command -v yamlfmt &>/dev/null; then
    yamlfmt "$f" -out "$tmp" &>/dev/null || { rm -f "$tmp"; printf "%s✗%s %s (yamlfmt failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1; }
    len_out=$(wc -c <"$tmp")
    mv "$tmp" "$f"
    printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
  else
    rm -f "$tmp"
    printf "%s⊘%s %s (yamlfmt not installed)\n" "$ylw" "$rst" "${f##*/}"
    return 0
  fi
}
export -f fmt_yaml
export ylw

process(){
  local -a css=() html=() json=() yaml=()
  if command -v fd &>/dev/null; then
    mapfile -t css < <(fd -ecss -tf -E'*.min.css' -Enode_modules -Edist . "$out" 2>/dev/null)
    mapfile -t html < <(fd -ehtml -ehtm -tf -Enode_modules -Edist . "$out" 2>/dev/null)
    mapfile -t json < <(fd -ejson -tf -E'*.min.json' -E'package*.json' -Enode_modules -E.git . "$out" 2>/dev/null)
    mapfile -t yaml < <(fd -eyml -eyaml -tf -Enode_modules -Edist . "$out" 2>/dev/null)
  else
    mapfile -t css < <(find "$out" -type f -name '*.css' ! -name '*.min.css' ! -path '*/node_modules/*' ! -path '*/dist/*' 2>/dev/null)
    mapfile -t html < <(find "$out" -type f \( -name '*.html' -o -name '*.htm' \) ! -path '*/node_modules/*' ! -path '*/dist/*' 2>/dev/null)
    mapfile -t json < <(find "$out" -type f -name '*.json' ! -name '*.min.json' ! -name 'package*.json' ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null)
    mapfile -t yaml < <(find "$out" -type f \( -name '*.yml' -o -name '*.yaml' \) ! -path '*/node_modules/*' ! -path '*/dist/*' 2>/dev/null)
  fi
  local -i total=$(( ${#css[@]} + ${#html[@]} + ${#json[@]} + ${#yaml[@]} ))
  (( total == 0 )) && { printf "%s⊘%s No files found\n" "$ylw" "$rst"; return 0; }
  if command -v rust-parallel &>/dev/null; then
    (( ${#css[@]} > 0 )) && printf "%s\n" "${css[@]}" | rust-parallel -j"$jobs" minify_css {} || :
    (( ${#html[@]} > 0 )) && printf "%s\n" "${html[@]}" | rust-parallel -j"$jobs" minify_html {} || :
    (( ${#json[@]} > 0 )) && printf "%s\n" "${json[@]}" | rust-parallel -j"$jobs" minify_json {} || :
    (( ${#yaml[@]} > 0 )) && printf "%s\n" "${yaml[@]}" | rust-parallel -j"$jobs" fmt_yaml {} || :
  elif command -v parallel &>/dev/null; then
    (( ${#css[@]} > 0 )) && printf "%s\n" "${css[@]}" | parallel -j"$jobs" minify_css {} || :
    (( ${#html[@]} > 0 )) && printf "%s\n" "${html[@]}" | parallel -j"$jobs" minify_html {} || :
    (( ${#json[@]} > 0 )) && printf "%s\n" "${json[@]}" | parallel -j"$jobs" minify_json {} || :
    (( ${#yaml[@]} > 0 )) && printf "%s\n" "${yaml[@]}" | parallel -j"$jobs" fmt_yaml {} || :
  else
    for f in "${css[@]}"; do minify_css "$f" || :; done
    for f in "${html[@]}"; do minify_html "$f" || :; done
    for f in "${json[@]}"; do minify_json "$f" || :; done
    for f in "${yaml[@]}"; do fmt_yaml "$f" || :; done
  fi
  printf "\n%s✓%s Processed %d files\n" "$grn" "$rst" "$total"
}

main(){ check_deps; process; }
main
