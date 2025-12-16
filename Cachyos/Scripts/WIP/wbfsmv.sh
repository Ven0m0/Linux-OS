#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

convert=1 trim=1 dry=0 verbose=0
readonly REGION=${WBFSMV_REGION:-PAL}
while (($#)) && [[ $1 == -* ]]; do
  case $1 in
    -c|--convert) convert=1 ;;
    --no-convert) convert=0 ;;
    -t|--trim) trim=1 ;;
    --no-trim) trim=0 ;;
    -n|--dry-run) dry=1 ;;
    -v|--verbose) verbose=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: wbfsmv.sh [options] [target_dir]
Options:
  -c, --convert      Convert to WBFS (default: on)
      --no-convert   Do not convert
  -t, --trim         Trim/scrub via wit (default: on)
      --no-trim      Do not trim
  -n, --dry-run      Show actions only
  -v, --verbose      Print progress
Environment:
  WBFSMV_REGION      PAL|NTSC|JAP|KOR|FREE [default: PAL]
Defaults: trim+convert on; outputs go through wit --wbfs --trim --psel=data,-update.
EOF
      exit 0 ;;
    *) printf 'Unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac; shift
done
TARGET=${1:-.}
[[ -d $TARGET ]] || { printf 'Not a directory: %s\n' "$TARGET" >&2; exit 2; }
command -v dd &>/dev/null || { printf 'dd required\n' >&2; exit 1; }
have_wit=0
command -v wit &>/dev/null && have_wit=1
((trim || convert)) && ((!have_wit)) && { printf 'wit required for trim/convert\n' >&2; exit 1; }
declare -rA region_map=([PAL]=EUROPE [NTSC]=USA [JAP]=JAPAN [KOR]=KOREA [FREE]=FREE)
readonly wit_region=${region_map[${REGION^^}]:-EUROPE}
log(){ ((verbose)) && printf '%s\n' "$*" >&2 || :; }
run(){ ((dry)) && log "[dry] $*" || "$@"; }
get_id(){
  local f=$1 id='' off=0
  [[ ${f,,} == *.wbfs ]] && off=512
  if ((have_wit)); then id=$(wit ID6 -- "$f" 2>/dev/null | awk 'NR==1{print;exit}' || printf ''); fi
  [[ -z $id ]] && id=$(dd if="$f" bs=1 skip="$off" count=6 2>/dev/null | tr -dc 'A-Za-z0-9')
  printf '%s' "${id^^}"
}
get_title(){
  ((have_wit)) || return 0
  wit dump -ll -- "$1" 2>/dev/null | awk -F': ' 'tolower($1)~/^(disc )?title[[:space:]]*:$/||tolower($1)~/^game title[[:space:]]*:$/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2);print $2;exit}'
}
clean(){
  local s=${1//_/ }
  s=$(printf '%s' "$s" | sed -E '
    s/[[:space:]]*\(([A-Z][a-z](,[A-Z][a-z])+)\)//g;
    s/[[:space:]]*\[([A-Z][a-z](,[A-Z][a-z])+)\]//g;
    s/[[:space:]]*\((Europe|USA?|Japan|Asia|World|PAL|NTSC|Rev[[:space:]]*[0-9]*)\)//gi;
    s/[[:space:]]*\[(Europe|USA?|Japan|Asia|World|PAL|NTSC|Rev[[:space:]]*[0-9]*)\]//gi;
    s/[[:space:]]+(PAL|NTSC|Europe|USA?|Japan|Asia|World)$//gi;
    s/[[:space:]]+/ /g; s/^ //; s/ $//; s/[[:space:]\/-]+$//
  ')
  printf '%s' "$s"
}
set_region(){
  ((have_wit)) || return 0
  local f=$1 cur
  cur=$(wit dump -ll -- "$f" 2>/dev/null | awk -F': ' '/^Region[[:space:]]*:/{print $2;exit}')
  [[ ${cur^^} == "${wit_region^^}" ]] && return 0
  log "set region $wit_region: $f"
  run wit edit --region "$wit_region" -q -- "$f" || :
}
trim_game(){
  log "trim: $1 -> $2"
  run wit copy --wbfs --trim --psel=data,-update -q -- "$1" "$2"
}
readonly exts=(wbfs iso ciso wia wdf)
is_game_ext(){
  local f=${1,,} e
  for e in "${exts[@]}"; do [[ $f == *."$e" ]] && return 0; done
  return 1
}
process_file(){
  local f=$1 id title name newdir ext base dest
  is_game_ext "$f" || return 0
  base=${f##*/}
  if [[ $base =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}
  else
    id=$(get_id "$f"); [[ ${#id} -eq 6 ]] || { log "skip (no ID): $f"; return 0; }
  fi
  title=$(get_title "$f")
  if [[ -n $title ]]; then
    name=$(clean "$title")
  else
    name=$(clean "${base%.*}")
    name=${name//\[$id\]/}
    name=$(printf '%s' "$name" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
  fi
  [[ -n $name ]] || name="Unknown"
  newdir="$TARGET/${name} [${id}]"
  ext=${f##*.}; ext=${ext,,}
  dest="$newdir/${id}.wbfs"
  if ((trim)) && ((have_wit)); then
    log "file: $f -> $dest"
    run mkdir -p -- "$newdir"
    if trim_game "$f" "$dest"; then
      set_region "$dest"
      [[ $f -ef $dest ]] 2>/dev/null || { log "removing original: $f"; run rm -f -- "$f"; }
    else
      log "trim failed, keeping original layout"
    fi
    return 0
  fi
  if [[ $ext == wbfs ]] && [[ $f -ef $dest ]] 2>/dev/null; then
    set_region "$f"; log "skip (already ok): $f"; return 0
  fi
  log "file: $f -> $dest"
  run mkdir -p -- "$newdir"
  if ((convert)) && [[ $ext != wbfs ]] && ((have_wit)); then
    if run wit copy --wbfs -q -- "$f" "$dest"; then
      set_region "$dest"; log "converted, removing original: $f"; run rm -f -- "$f"
    else
      log "convert failed, moving as-is"
      run mv -n -- "$f" "$newdir/${id}.${ext}"
      set_region "$newdir/${id}.${ext}"
    fi
  else
    local target_file="$newdir/${id}.${ext}"
    run mv -n -- "$f" "$target_file"
    set_region "$target_file"
  fi
}
process_dir(){
  local d=$1 id='' g='' title name newdir base=${d##*/}
  [[ $base =~ \[[A-Z0-9]{6}\] ]] && { log "skip (already tagged): $d"; return 0; }
  local e cand
  for e in "${exts[@]}"; do
    for cand in "$d"/*."$e"; do
      [[ -f $cand ]] || continue
      id=$(get_id "$cand")
      [[ ${#id} -eq 6 ]] && { g=$cand; break 2; }
    done
  done
  [[ ${#id} -eq 6 ]] || { log "skip (no game found): $d"; return 0; }
  title=$(get_title "$g")
  name=$(clean "${title:-$base}"); [[ -n $name ]] || name="Unknown"
  newdir="$TARGET/${name} [${id}]"
  [[ $d -ef $newdir ]] 2>/dev/null && ((!trim)) && { log "skip (already ok): $d"; return 0; }
  if [[ -e $newdir ]] && ! [[ $d -ef $newdir ]]; then
    log "skip (target exists): $newdir"; return 0
  fi
  if ! [[ $d -ef $newdir ]]; then
    log "dir: $d -> $newdir"; run mv -n -- "$d" "$newdir"
  fi
  local gf gid gbase gext gdest tmp
  for e in "${exts[@]}"; do
    for gf in "$newdir"/*."$e"; do
      [[ -f $gf ]] || continue
      gid=$(get_id "$gf"); [[ ${#gid} -eq 6 ]] || continue
      gbase=${gf##*/}; gext=${gf##*.}; gext=${gext,,}; gdest="$newdir/${gid}.wbfs"
      if ((trim)) && ((have_wit)); then
        if [[ $gf -ef $gdest ]] 2>/dev/null; then
          tmp="$newdir/.trim_tmp_${gid}.wbfs"
          if trim_game "$gf" "$tmp"; then run mv -f -- "$tmp" "$gdest"; set_region "$gdest"; else run rm -f -- "$tmp" || :; fi
        else
          if trim_game "$gf" "$gdest"; then set_region "$gdest"; run rm -f -- "$gf"; fi
        fi
      elif ((convert)) && [[ $gext != wbfs ]] && ((have_wit)); then
        if run wit copy --wbfs -q -- "$gf" "$gdest"; then set_region "$gdest"; run rm -f -- "$gf"; fi
      elif [[ $gbase != "${gid}.${gext}" ]]; then
        run mv -n -- "$gf" "$newdir/${gid}.${gext}"; set_region "$newdir/${gid}.${gext}"
      else
        set_region "$gf"
      fi
    done
  done
}
for entry in "$TARGET"/*; do
  [[ -e $entry ]] || continue
  [[ -f $entry ]] && process_file "$entry"
  [[ -d $entry ]] && process_dir "$entry"
done
log "done"
