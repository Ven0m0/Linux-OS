#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
export LC_ALL=C LANG=C LANGUAGE=C; IFS=$'\n\t'
readonly out="${1:-.}"
readonly jobs=$(nproc 2>/dev/null || echo 4)
readonly red=$'\e[31m' grn=$'\e[32m' ylw=$'\e[33m' rst=$'\e[0m'
has(){ command -v "$1" &>/dev/null; }
check_deps(){
  local -a missing=()
  has minify || has bunx || has npx || missing+=(minify/bun/node)
  has jaq || has jq || has minify || missing+=(jaq/jq/minify)
  ((${#missing[@]} > 0)) && { printf "%s✗%s Missing: %s\n" "$red" "$rst" "${missing[*]}" >&2; exit 1; }
}
minify_css(){
  local f=$1 tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  [[ $f =~ \.min\.css$ ]] && return 0
  if has minify; then
    minify --type css -o "$tmp" "$f" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (minify failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  elif has bunx; then
    bunx --bun lightningcss --minify "$f" -o "$tmp" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (lightningcss failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  elif has npx; then
    npx -y lightningcss --minify "$f" -o "$tmp" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (lightningcss failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  else
    rm -f "$tmp"; printf "%s⊘%s %s (no css minifier)\n" "$ylw" "$rst" "${f##*/}"; return 0
  fi
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_css; export grn red rst ylw
minify_html(){
  local f=$1 tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  if has minify; then
    minify --type html -o "$tmp" "$f" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (minify failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  else
    rm -f "$tmp"; printf "%s⊘%s %s (minify not installed)\n" "$ylw" "$rst" "${f##*/}"; return 0
  fi
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_html
minify_json(){
  local f="$1" tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  [[ $f =~ \.min\.json$|package(-lock)?\.json$ ]] && return 0
  if has jaq; then
    jaq -c . "$f" > "$tmp" 2>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (jaq failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  elif has jq; then
    jq -c . "$f" > "$tmp" 2>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (jq failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  elif has minify; then
    minify --type json -o "$tmp" "$f" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (minify failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  else
    rm -f "$tmp"; printf "%s⊘%s %s (no json minifier)\n" "$ylw" "$rst" "${f##*/}"; return 0
  fi
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_json
minify_xml(){
  local f="$1" tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  [[ $f =~ \.min\.xml$ ]] && return 0
  if has minify; then
    minify --type xml -o "$tmp" "$f" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (minify failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  elif has xmllint; then
    xmllint --noblanks "$f" > "$tmp" 2>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (xmllint failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
  else
    rm -f "$tmp"; printf "%s⊘%s %s (no xml minifier)\n" "$ylw" "$rst" "${f##*/}"; return 0
  fi
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f minify_xml
minify_pdf(){
  local f="$1" tmp_gs=$(mktemp --suffix=.pdf) tmp_pop=$(mktemp --suffix=.pdf)
  local len_in=$(wc -c < "$f") len_gs len_pop
  [[ $f =~ \.min\.pdf$ ]] && return 0
  if has pdfinfo; then
    local prod=$(pdfinfo "$f" 2>/dev/null | grep -F Producer || :)
    if [[ $prod =~ Ghostscript|cairo ]]; then
      printf "%s⊘%s %s (already processed)\n" "$ylw" "$rst" "${f##*/}"
      rm -f "$tmp_gs" "$tmp_pop"
      return 0
    fi
  fi
  local gs_ok=0 pop_ok=0
  if has gs; then
    gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 \
      -dDetectDuplicateImages=true -dSubsetFonts=true -dCompressFonts=true \
      -sOutputFile="$tmp_gs" -c 33550336 setvmthreshold -f "$f" &>/dev/null && gs_ok=1 || rm -f "$tmp_gs"
  fi
  if has pdftocairo; then
    pdftocairo -pdf "$f" "$tmp_pop" &>/dev/null && pop_ok=1 || rm -f "$tmp_pop"
  fi
  if [[ $gs_ok -eq 0 && $pop_ok -eq 0 ]]; then
    printf "%s✗%s %s (gs+cairo failed)\n" "$red" "$rst" "${f##*/}" >&2
    rm -f "$tmp_gs" "$tmp_pop"
    return 1
  fi
  [[ $gs_ok -eq 1 ]] && len_gs=$(wc -c < "$tmp_gs") || len_gs=999999999
  [[ $pop_ok -eq 1 ]] && len_pop=$(wc -c < "$tmp_pop") || len_pop=999999999
  if [[ $len_pop -lt $len_gs && $len_pop -lt $len_in ]]; then
    mv -f "$tmp_pop" "$f"
    rm -f "$tmp_gs"
    printf "%s✓%s %s (%d → %d, cairo)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_pop"
  elif [[ $len_gs -lt $len_in ]]; then
    mv -f "$tmp_gs" "$f"
    rm -f "$tmp_pop"
    printf "%s✓%s %s (%d → %d, gs)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_gs"
  else
    rm -f "$tmp_gs" "$tmp_pop"
    printf "%s⊘%s %s (no reduction)\n" "$ylw" "$rst" "${f##*/}"
  fi
}
export -f minify_pdf
fmt_yaml(){
  local f="$1" tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  if has yamlfmt; then
    yamlfmt -q "$f" -out "$tmp" &>/dev/null || {
      rm -f "$tmp"; printf "%s✗%s %s (yamlfmt failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
    }
    len_out=$(wc -c < "$tmp")
    mv -f "$tmp" "$f"
    printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
  else
    rm -f "$tmp"; printf "%s⊘%s %s (yamlfmt not installed)\n" "$ylw" "$rst" "${f##*/}"; return 0
  fi
}
export -f fmt_yaml
process(){
  local -a css=() html=() json=() xml=() pdf=() yaml=()
  local ex='-Enode_modules -Edist -E.git -E.cache -Ebuild -Etarget -E__pycache__ -E.venv -E.npm -Evendor'
  if has fd; then
    mapfile -t css < <(fd -ecss -tf -E'*.min.css' $ex . "$out" 2>/dev/null)
    mapfile -t html < <(fd -ehtml -ehtm -tf $ex . "$out" 2>/dev/null)
    mapfile -t json < <(fd -ejson -tf -E'*.min.json' -E'package*.json' $ex . "$out" 2>/dev/null)
    mapfile -t xml < <(fd -exml -tf -E'*.min.xml' $ex . "$out" 2>/dev/null)
    mapfile -t pdf < <(fd -epdf -tf -E'*.min.pdf' $ex . "$out" 2>/dev/null)
    mapfile -t yaml < <(fd -eyml -eyaml -tf $ex . "$out" 2>/dev/null)
  else
    local fp='! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.cache/*" ! -path "*/build/*" ! -path "*/target/*" ! -path "*/__pycache__/*" ! -path "*/.venv/*" ! -path "*/.npm/*" ! -path "*/vendor/*"'
    mapfile -t css < <(eval "find '$out' -type f -name '*.css' ! -name '*.min.css' $fp 2>/dev/null")
    mapfile -t html < <(eval "find '$out' -type f \\( -name '*.html' -o -name '*.htm' \\) $fp 2>/dev/null")
    mapfile -t json < <(eval "find '$out' -type f -name '*.json' ! -name '*.min.json' ! -name 'package*.json' $fp 2>/dev/null")
    mapfile -t xml < <(eval "find '$out' -type f -name '*.xml' ! -name '*.min.xml' $fp 2>/dev/null")
    mapfile -t pdf < <(eval "find '$out' -type f -name '*.pdf' ! -name '*.min.pdf' $fp 2>/dev/null")
    mapfile -t yaml < <(eval "find '$out' -type f \\( -name '*.yml' -o -name '*.yaml' \\) $fp 2>/dev/null")
  fi
  local -i total=$((${#css[@]} + ${#html[@]} + ${#json[@]} + ${#xml[@]} + ${#pdf[@]} + ${#yaml[@]}))
  ((total == 0)) && { printf "%s⊘%s No files found\n" "$ylw" "$rst"; return 0; }
  if has rust-parallel; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | rust-parallel -j"$jobs" minify_css {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | rust-parallel -j"$jobs" minify_html {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | rust-parallel -j"$jobs" minify_json {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | rust-parallel -j"$jobs" minify_xml {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | rust-parallel -j"$jobs" minify_pdf {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | rust-parallel -j"$jobs" fmt_yaml {} || :
  elif has parallel; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | parallel -j"$jobs" minify_css {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | parallel -j"$jobs" minify_html {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | parallel -j"$jobs" minify_json {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | parallel -j"$jobs" minify_xml {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | parallel -j"$jobs" minify_pdf {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | parallel -j"$jobs" fmt_yaml {} || :
  elif has xargs; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_css "$@"' _ {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_html "$@"' _ {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_json "$@"' _ {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_xml "$@"' _ {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_pdf "$@"' _ {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | xargs -r -P"$jobs" -I{} bash -c 'fmt_yaml "$@"' _ {} || :
  else
    for f in "${css[@]}"; do minify_css "$f" || :; done
    for f in "${html[@]}"; do minify_html "$f" || :; done
    for f in "${json[@]}"; do minify_json "$f" || :; done
    for f in "${xml[@]}"; do minify_xml "$f" || :; done
    for f in "${pdf[@]}"; do minify_pdf "$f" || :; done
    for f in "${yaml[@]}"; do fmt_yaml "$f" || :; done
  fi
  printf "\n%s✓%s Processed %d files\n" "$grn" "$rst" "$total"
}
check_deps
process
