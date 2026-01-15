#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# wbfsmv - Wii game library organizer (USB Loader GX format)
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

has(){ command -v -- "$1" &>/dev/null; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }
log(){ if ((VERB)); then printf '%s\n' "$@" >&2; fi; }
run(){ if ((DRY)); then printf '[dry] %s\n' "$*" >&2; else "$@"; fi; }
CONV=1 DRY=0 VERB=0 REGION=${WBFSMV_REGION:-PAL}
CACHE_DIR=${XDG_CACHE_HOME:-${HOME}/.cache}/wbfsmv
CACHE_DB=${CACHE_DIR}/gametdb_wii.txt
CACHE_MAX_AGE=$((30*86400))
usage(){ printf 'Usage: %s [-c|--convert] [--no-convert] [-n|--dry-run] [-v|--verbose] [-r REGION] [DIR]\n' "${0##*/}"; exit 0; }

while [[ ${1:-} == -* ]]; do
  case $1 in
    -c|--convert) CONV=1 ;;
    --no-convert) CONV=0 ;;
    -n|--dry-run) DRY=1 VERB=1 ;;
    -v|--verbose) VERB=1 ;;
    -r|--region) REGION=${2:-PAL}; shift ;;
    -h|--help) usage ;;
    --) shift; break ;;
    *) die "Unknown option: $1" 2 ;;
  esac
  shift
done
TGT=${1:-.}
[[ -d ${TGT} ]] || die "Not a directory: ${TGT}" 2

HAS_WIT=0
has dd || die "Requires: dd" 1
if has wit; then HAS_WIT=1; fi
((CONV && !HAS_WIT)) && die "Requires: wit (Wiimms ISO Tools) for conversion" 1
HTTP_CMD=()
if has curl; then HTTP_CMD=(curl -fsSL -A 'wbfsmv/1.0' -o)
elif has wget; then HTTP_CMD=(wget -qO)
elif has aria2c; then HTTP_CMD=(aria2c -q --allow-overwrite=true -o)
else log "Warning: No HTTP client; GameTDB lookup disabled"; fi

declare -rA RMAP=([PAL]=EUROPE [NTSC]=USA [JAP]=JAPAN [KOR]=KOREA [FREE]=FREE)
WREG=${RMAP[${REGION^^}]:-EUROPE}
update_cache(){
  ((${#HTTP_CMD[@]})) || return 1
  mkdir -p "$CACHE_DIR"
  local tmp=${CACHE_DIR}/dl.$$.tmp
  if "${HTTP_CMD[@]}" "$tmp" "https://www.gametdb.com/wiitdb.txt?LANG=EN" 2>/dev/null; then
    if [[ -s ${tmp} ]]; then mv -f "$tmp" "$CACHE_DB"; log "GameTDB cache updated"; return 0; fi
  fi
  rm -f "$tmp"
  return 1
}
load_cache(){
  if [[ -f ${CACHE_DB} ]]; then
    local mtime age now
    mtime=$(stat -c%Y "$CACHE_DB" 2>/dev/null) || mtime=0
    printf -v now '%(%s)T' -1
    age=$((now - mtime))
    if ((age > CACHE_MAX_AGE)); then update_cache || :; fi
  else
    update_cache || return 1
  fi
  [[ -f ${CACHE_DB} ]]
}
lookup_gametdb(){
  local id=$1 key val
  load_cache || return 1
  while IFS='=' read -r key val; do
    [[ ${key^^} == "${id^^}" ]] && { printf '%s\n' "$val"; return 0; }
  done <"$CACHE_DB"
  return 1
}
get_id(){
  local f=$1 id="" skip=0
  [[ ${f,,} == *.wbfs ]] && skip=512
  if [[ ${f##*/} =~ \[([A-Z0-9]{4,6})\] ]]; then
    id=${BASH_REMATCH[1]}
  elif ((HAS_WIT)); then
    id=$(wit ID6 -- "$f" 2>/dev/null) || id=""
    id=${id%%$'\n'*}
  fi
  if [[ -z ${id} || ${#id} -lt 4 ]]; then
    id=$(dd if="$f" bs=1 skip="$skip" count=6 2>/dev/null | tr -dc 'A-Za-z0-9') || id=""
  fi
  printf '%s\n' "${id^^}"
}
get_title(){
  local f=$1 id=$2 t="" key val dump
  if ((HAS_WIT)); then
    dump=$(wit dump -ll -- "$f" 2>/dev/null) || dump=""
    while IFS=':' read -r key val; do
      key=${key,,}; key=${key// /}
      if [[ ${key} == disctitle || ${key} == gametitle ]]; then
        t=${val#"${val%%[![:space:]]*}"}; t=${t%"${t##*[![:space:]]}"}; break
      fi
    done <<<"$dump"
  fi
  if [[ -z ${t} ]]; then t=$(lookup_gametdb "$id") || t=""; fi
  printf '%s\n' "$t"
}
clean(){
  local s=$1 re_paren re_brack
  s=${s//_/ }
  # Remove parenthetical/bracketed content (assign regex to var for shellcheck)
  re_paren='[(][^)]*[)]'
  re_brack='\[[^]]*\]'
  while [[ ${s} =~ ${re_paren} ]]; do s=${s//"${BASH_REMATCH[0]}"/ }; done
  while [[ ${s} =~ ${re_brack} ]]; do s=${s//"${BASH_REMATCH[0]}"/ }; done
  # Strip filesystem-unsafe chars: : \ / * ? " < > |
  s=${s//:/}; s=${s//\\/}; s=${s//\//}; s=${s//\*/}
  s=${s//\?/}; s=${s//\"/}; s=${s//</}; s=${s//>/}; s=${s//|/}
  # Collapse whitespace
  while [[ ${s} == *'  '* ]]; do s=${s//  / }; done
  s=${s# }; s=${s% }
  printf '%s\n' "$s"
}
set_reg(){
  ((HAS_WIT)) || return 0
  local f=$1 cur="" key val dump
  dump=$(wit dump -ll -- "$f" 2>/dev/null) || return 0
  while IFS=':' read -r key val; do
    if [[ ${key,,} == *region* ]]; then
      cur=${val#"${val%%[![:space:]]*}"}; cur=${cur%"${cur##*[![:space:]]}"}; break
    fi
  done <<<"$dump"
  [[ ${cur^^} == "${WREG^^}" ]] && return 0
  log "Region: ${cur} -> ${WREG}: ${f##*/}"
  run wit edit --region "$WREG" -q -- "$f"
}
is_game(){ [[ ${1,,} =~ \.(wbfs|iso|ciso|wia|wdf)$ ]]; }
proc_file(){
  local f=$1 id t name ndir ext dst
  is_game "$f" || return 0
  id=$(get_id "$f")
  [[ ${#id} -ge 4 ]] || { log "Skip (no ID): ${f}"; return 0; }
  t=$(get_title "$f" "$id")
  if [[ -z ${t} ]]; then t=$(clean "${f##*/}"); fi
  name=$(clean "$t")
  if [[ -z ${name} ]]; then name="Unknown"; fi
  ndir="${TGT}/${name} [${id}]"
  ext=${f##*.}; ext=${ext,,}
  dst="${ndir}/${id}.wbfs"
  # Already in place?
  if [[ ${ext} == wbfs && -d ${ndir} && ${f##*/} == "${id}.wbfs" ]]; then
    local cwd_ndir cwd_fdir
    cwd_ndir=$(cd "$ndir" && pwd) || cwd_ndir=""
    cwd_fdir=$(cd "${f%/*}" && pwd) || cwd_fdir=""
    if [[ ${cwd_ndir} == "$cwd_fdir" ]]; then set_reg "$f"; return 0; fi
  fi
  run mkdir -p "$ndir"
  if ((CONV && HAS_WIT)) && [[ ${ext} != wbfs ]]; then
    if run wit copy --wbfs -q -- "$f" "$dst"; then
      set_reg "$dst"; run rm -f "$f"
    else
      run mv -n -- "$f" "${ndir}/${id}.${ext}"; set_reg "${ndir}/${id}.${ext}"
    fi
  else
    run mv -n -- "$f" "${ndir}/${id}.${ext}"
    set_reg "${ndir}/${id}.${ext}"
  fi
}
proc_dir(){
  local dir=$1 base=${1##*/} id="" t name ndir f gid ext dst
  if [[ ${base} =~ \[([A-Z0-9]{4,6})\]$ ]]; then
    id=${BASH_REMATCH[1]}
    t=$(clean "${base%% \[*}")
    if [[ -z ${t} ]]; then
      for f in "$dir"/*.{wbfs,iso,ciso,wia,wdf}; do
        [[ -f ${f} ]] || continue
        t=$(get_title "$f" "$id")
        if [[ -n ${t} ]]; then break; fi
      done
    fi
    if [[ -z ${t} ]]; then t="Unknown"; fi
    name="${t} [${id}]"
    ndir="${TGT}/${name}"
    if [[ ${dir} != "$ndir" ]] && ! [[ -d ${ndir} ]]; then
      log "Rename: ${base} -> ${name}"
      if run mv -n -- "$dir" "$ndir"; then dir=${ndir}; fi
    fi
  fi
  for f in "$dir"/*.{wbfs,iso,ciso,wia,wdf}; do
    [[ -f ${f} ]] || continue
    gid=$(get_id "$f")
    [[ ${#gid} -ge 4 ]] || { log "Skip (no ID): ${f}"; continue; }
    ext=${f##*.}; ext=${ext,,}
    dst="${dir}/${gid}.wbfs"
    if ((CONV && HAS_WIT)) && [[ ${ext} != wbfs ]]; then
      if run wit copy --wbfs -q -- "$f" "$dst"; then
        set_reg "$dst"; run rm -f "$f"
      fi
    elif [[ ${f##*/} != "${gid}.${ext}" ]]; then
      run mv -n -- "$f" "${dir}/${gid}.${ext}"
      set_reg "${dir}/${gid}.${ext}"
    else
      set_reg "$f"
    fi
  done
}
main(){
  local x
  for x in "$TGT"/*; do
    if [[ -f ${x} ]]; then proc_file "$x"; fi
    if [[ -d ${x} ]]; then proc_dir "$x"; fi
  done
  log "Done: ${TGT}"
}
main
