#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob
export LC_ALL=C LANG=C LANGUAGE=C; IFS=$'\n\t'
readonly out="${1:-.}"
readonly jobs=$(nproc 2>/dev/null || echo 4)
readonly red=$'\e[31m' grn=$'\e[32m' ylw=$'\e[33m' rst=$'\e[0m'
has(){ command -v -- "$1" &>/dev/null; }
check_deps(){
  local -a missing=()
  has minify || has bunx || has npx || missing+=(minify/bun/node)
  has jaq || has jq || has minify || missing+=(jaq/jq/minify)
  has awk || missing+=(awk)
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
  local f="$1" tmp=$(mktemp --suffix=.pdf) len_in=$(wc -c < "$f") len_out tool
  [[ $f =~ \.min\.pdf$ ]] && return 0
  if has pdfinfo; then
    local prod=$(pdfinfo "$f" 2>/dev/null | grep -F Producer || :)
    [[ $prod =~ Ghostscript|cairo ]] && {
      printf "%s⊘%s %s (already processed)\n" "$ylw" "$rst" "${f##*/}"; rm -f "$tmp"; return 0
    }
  fi
  if has qpdf && qpdf --linearize --object-streams=generate --compress-streams=y --recompress-flate "$f" "$tmp" &>/dev/null; then
    tool=qpdf
  elif has gs && gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -dCompatibilityLevel=1.7 \
    -dDetectDuplicateImages=true -dSubsetFonts=true -dCompressFonts=true \
    -sOutputFile="$tmp" -c 33550336 setvmthreshold -f "$f" &>/dev/null; then
    tool=gs
  else
    rm -f "$tmp"; printf "%s✗%s %s (no optimizer)\n" "$red" "$rst" "${f##*/}" >&2; return 1
  fi
  len_out=$(wc -c < "$tmp")
  if ((len_out < len_in)); then
    mv -f "$tmp" "$f"
    printf "%s✓%s %s (%d → %d, %s)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out" "$tool"
  else
    rm -f "$tmp"; printf "%s⊘%s %s (no reduction)\n" "$ylw" "$rst" "${f##*/}"
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
fmt_ini(){
  local f="$1" tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  awk 'function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s);return s}
    /^[ \t]*([;#]|$)/ {print; next}
    /^[ \t]*\[/       {print t($0); next}
    match($0,/=/)     {print t(substr($0,1,RSTART-1)) " = " t(substr($0,RSTART+1)); next}
  ' "$f" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"; printf "%s✗%s %s (awk failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
  }
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f fmt_ini
fmt_conf(){
  local f="$1" tmp=$(mktemp) len_in=$(wc -c < "$f") len_out
  # shellcheck disable=SC1036,SC1056
  awk 'BEGIN{FS=" +";placeholder="\033";align_all_columns=z_get_var(align_all_columns,0);align_columns_if_first_matches=align_all_columns?0:z_get_var(align_columns_if_first_matches,0);align_columns=align_all_columns||align_columns_if_first_matches;align_comments=z_get_var(align_comments,1);comment_regex=align_comments?z_get_var(comment_regex,"[#;]"):""}/^[[:blank:]]*$/{if(!last_empty){c_print_section();if(output_lines){empty_pending=1}}last_empty=1;next}{sub(/^ +/,"",$0);if(empty_pending){print"";empty_pending=0}last_empty=0;if(align_columns_if_first_matches&&actual_lines&&(!comment_regex||$1!~"^"comment_regex"([^[:blank:]]|$)")&&$1!=setting){b_queue_entries()}entry_line++;section_line++;field_count[entry_line]=0;comment[section_line]="";for(i=1;i<=NF;i++){if(a_process_regex("[\"'\\\\]","(([^ \"'\''\\\\]|\\\\.)*(\"([^\"]|\\\\\")*\"|'\''([^'\'']|\\\\\\')*'\''))*([^ \\\\]|\\\\.|\\\\$)*")){a_store_field(field_value)}else if(comment_regex&&(a_process_regex(comment_regex,comment_regex".*",1))){sub(/ +$/,"",field_value);comment[section_line]=field_value}else if(length($i)){a_store_field($i"");a_replace_field(placeholder)}}if(field_count[entry_line]){if(!actual_lines){setting=entry[entry_line,1]}actual_lines++}}END{c_print_section()}function a_process_regex(r,v,s,_p,_d){if(match($i,r)){if(s&&RSTART>1){a_replace_field(substr($i,1,RSTART-1)" "substr($i,RSTART));return}_p=$0;sub("^( |"placeholder")*","",_p);if(match(_p,"^"v)){field_value=substr(_p,RSTART,RLENGTH);_d=length($0)-length(_p);$0=substr($0,1,RSTART-1+_d)placeholder substr($0,RSTART+RLENGTH+_d);return 1}}}function a_replace_field(v,_n){if(!match($0,"^ *[^ ]+( +[^ ]+){"(i-1)"}")){$i=v;return}_n=substr($0,RLENGTH+1);$0=substr($0,1,RLENGTH);$i="";$0=$0 v _n}function a_store_field(v,_l){field_count[entry_line]=i;entry[entry_line,i]=v;_l=length(v);field_width[i]=_l>field_width[i]?_l:field_width[i]}function b_queue_entries(_o,_i,_j,_l){_o=section_line-entry_line;for(_i=1;_i<=entry_line;_i++){_l="";for(_j=1;_j<=field_count[_i];_j++){if(align_columns&&actual_lines>1&&setting){_l=_l sprintf("%-"field_width[_j]"s ",entry[_i,_j])}else{_l=_l sprintf("%s ",entry[_i,_j])}}sub(" $","",_l);section[_o+_i]=_l}entry_line=0;actual_lines=0;for(_j in field_width){delete field_width[_j]}}function c_print_section(_i,_len,_max,_l){b_queue_entries();for(_i=1;_i<=section_line;_i++){_len=length(section[_i]);_max=_len>_max?_len:_max}for(_i=1;_i<=section_line;_i++){_l=section[_i];if(comment[_i]){_l=(_l~/[^\t]/?sprintf("%-"_max"s ",_l):_l)comment[_i]}print _l;output_lines++}section_line=0}function z_get_var(v,d){return z_is_set(v)?v:d}function z_is_set(v){return!(v==""&&v==0)}' "$f" > "$tmp" 2>/dev/null || {
    rm -f "$tmp"; printf "%s✗%s %s (awk failed)\n" "$red" "$rst" "${f##*/}" >&2; return 1
  }
  len_out=$(wc -c < "$tmp")
  mv -f "$tmp" "$f"
  printf "%s✓%s %s (%d → %d)\n" "$grn" "$rst" "${f##*/}" "$len_in" "$len_out"
}
export -f fmt_conf
process(){
  local -a css=() html=() json=() xml=() pdf=() yaml=() ini=() conf=()
  local ex='-Enode_modules -Edist -E.git -E.cache -Ebuild -Etarget -E__pycache__ -E.venv -E.npm -Evendor'
  if has fd; then
    mapfile -t css < <(fd -ecss -tf -E'*.min.css' "$ex" . "$out" 2>/dev/null)
    mapfile -t html < <(fd -ehtml -ehtm -tf "$ex" . "$out" 2>/dev/null)
    mapfile -t json < <(fd -ejson -tf -E'*.min.json' -E'package*.json' "$ex" . "$out" 2>/dev/null)
    mapfile -t xml < <(fd -exml -tf -E'*.min.xml' "$ex" . "$out" 2>/dev/null)
    mapfile -t pdf < <(fd -epdf -tf -E'*.min.pdf' "$ex" . "$out" 2>/dev/null)
    mapfile -t yaml < <(fd -eyml -eyaml -tf "$ex" . "$out" 2>/dev/null)
    mapfile -t ini < <(fd -eini -tf "$ex" . "$out" 2>/dev/null)
    mapfile -t conf < <(fd -econf -ecfg -tf "$ex" . "$out" 2>/dev/null)
  else
    local fp='! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.cache/*" ! -path "*/build/*" ! -path "*/target/*" ! -path "*/__pycache__/*" ! -path "*/.venv/*" ! -path "*/.npm/*" ! -path "*/vendor/*"'
    mapfile -t css < <(eval "find '$out' -type f -name '*.css' ! -name '*.min.css' $fp 2>/dev/null")
    mapfile -t html < <(eval "find '$out' -type f \\( -name '*.html' -o -name '*.htm' \\) $fp 2>/dev/null")
    mapfile -t json < <(eval "find '$out' -type f -name '*.json' ! -name '*.min.json' ! -name 'package*.json' $fp 2>/dev/null")
    mapfile -t xml < <(eval "find '$out' -type f -name '*.xml' ! -name '*.min.xml' $fp 2>/dev/null")
    mapfile -t pdf < <(eval "find '$out' -type f -name '*.pdf' ! -name '*.min.pdf' $fp 2>/dev/null")
    mapfile -t yaml < <(eval "find '$out' -type f \\( -name '*.yml' -o -name '*.yaml' \\) $fp 2>/dev/null")
    mapfile -t ini < <(eval "find '$out' -type f -name '*.ini' $fp 2>/dev/null")
    mapfile -t conf < <(eval "find '$out' -type f \\( -name '*.conf' -o -name '*.cfg' \\) $fp 2>/dev/null")
  fi
  local -i total=$((${#css[@]} + ${#html[@]} + ${#json[@]} + ${#xml[@]} + ${#pdf[@]} + ${#yaml[@]} + ${#ini[@]} + ${#conf[@]}))
  ((total == 0)) && { printf "%s⊘%s No files found\n" "$ylw" "$rst"; return 0; }
  if has rust-parallel; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | rust-parallel -j"$jobs" minify_css {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | rust-parallel -j"$jobs" minify_html {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | rust-parallel -j"$jobs" minify_json {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | rust-parallel -j"$jobs" minify_xml {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | rust-parallel -j"$jobs" minify_pdf {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | rust-parallel -j"$jobs" fmt_yaml {} || :
    ((${#ini[@]} > 0)) && printf "%s\n" "${ini[@]}" | rust-parallel -j"$jobs" fmt_ini {} || :
    ((${#conf[@]} > 0)) && printf "%s\n" "${conf[@]}" | rust-parallel -j"$jobs" fmt_conf {} || :
  elif has parallel; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | parallel -j"$jobs" minify_css {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | parallel -j"$jobs" minify_html {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | parallel -j"$jobs" minify_json {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | parallel -j"$jobs" minify_xml {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | parallel -j"$jobs" minify_pdf {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | parallel -j"$jobs" fmt_yaml {} || :
    ((${#ini[@]} > 0)) && printf "%s\n" "${ini[@]}" | parallel -j"$jobs" fmt_ini {} || :
    ((${#conf[@]} > 0)) && printf "%s\n" "${conf[@]}" | parallel -j"$jobs" fmt_conf {} || :
  elif has xargs; then
    ((${#css[@]} > 0)) && printf "%s\n" "${css[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_css "$@"' _ {} || :
    ((${#html[@]} > 0)) && printf "%s\n" "${html[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_html "$@"' _ {} || :
    ((${#json[@]} > 0)) && printf "%s\n" "${json[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_json "$@"' _ {} || :
    ((${#xml[@]} > 0)) && printf "%s\n" "${xml[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_xml "$@"' _ {} || :
    ((${#pdf[@]} > 0)) && printf "%s\n" "${pdf[@]}" | xargs -r -P"$jobs" -I{} bash -c 'minify_pdf "$@"' _ {} || :
    ((${#yaml[@]} > 0)) && printf "%s\n" "${yaml[@]}" | xargs -r -P"$jobs" -I{} bash -c 'fmt_yaml "$@"' _ {} || :
    ((${#ini[@]} > 0)) && printf "%s\n" "${ini[@]}" | xargs -r -P"$jobs" -I{} bash -c 'fmt_ini "$@"' _ {} || :
    ((${#conf[@]} > 0)) && printf "%s\n" "${conf[@]}" | xargs -r -P"$jobs" -I{} bash -c 'fmt_conf "$@"' _ {} || :
  else
    for f in "${css[@]}"; do minify_css "$f" || :; done
    for f in "${html[@]}"; do minify_html "$f" || :; done
    for f in "${json[@]}"; do minify_json "$f" || :; done
    for f in "${xml[@]}"; do minify_xml "$f" || :; done
    for f in "${pdf[@]}"; do minify_pdf "$f" || :; done
    for f in "${yaml[@]}"; do fmt_yaml "$f" || :; done
    for f in "${ini[@]}"; do fmt_ini "$f" || :; done
    for f in "${conf[@]}"; do fmt_conf "$f" || :; done
  fi
  printf "\n%s✓%s Processed %d files\n" "$grn" "$rst" "$total"
}
check_deps
process
