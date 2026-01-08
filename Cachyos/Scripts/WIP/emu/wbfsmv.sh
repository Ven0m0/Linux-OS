#!/usr/bin/env bash
# wbfsmv.sh - Optimized Wii Backup Manager
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

# --- Config & Args ---
CONV=1 TRIM=1 DRY=0 VERB=0 REGION=${WBFSMV_REGION:-PAL}
while [[ ${1:-} == -* ]]; do
  case $1 in
  -c | --convert) CONV=1 ;; --no-convert) CONV=0 ;;
  -t | --trim) TRIM=1 ;; --no-trim) TRIM=0 ;;
  -n | --dry-run) DRY=1 ;; -v | --verbose) VERB=1 ;;
  -h | --help)
    echo "Usage: ${0##*/} [-c|-t|-n|-v] [DIR]"
    exit 0
    ;;
  *)
    echo "Err: $1" >&2
    exit 2
    ;;
  esac
  shift
done
TGT=${1:-.}
[[ -d $TGT ]] || {
  echo "No dir: $TGT" >&2
  exit 2
}
# --- Deps & Vars ---
command -v dd >/dev/null || {
  echo "Need dd" >&2
  exit 1
}
HAS_WIT=0
command -v wit >/dev/null && HAS_WIT=1
((TRIM || CONV)) && ((!HAS_WIT)) && {
  echo "Need wit for trim/convert" >&2
  exit 1
}
declare -rA RMAP=([PAL]=EUROPE [NTSC]=USA [JAP]=JAPAN [KOR]=KOREA [FREE]=FREE)
WREG=${RMAP[${REGION^^}]:-EUROPE}
# --- Helpers ---
log() { ((VERB)) && echo "$@" >&2 || :; }
run() { ((DRY)) && log "[dry] $*" || "$@"; }
get_id() {
  local f=$1 i s=0
  [[ ${f,,} == *.wbfs ]] && s=512
  ((HAS_WIT)) && i=$(wit ID6 -- "$f" 2>/dev/null | awk 'NR==1{print;exit}')
  [[ -z ${i:-} ]] && i=$(dd if="$f" bs=1 skip=$s count=6 2>/dev/null | tr -dc 'A-Za-z0-9')
  echo "${i^^}"
}
get_title() { ((HAS_WIT)) && wit dump -ll -- "$1" 2>/dev/null | awk -F': ' 'tolower($1)~/^(disc|game) title\s*$/{gsub(/^\s+|\s+$/,"",$2);print $2;exit}'; }
clean() { sed -E 's/[[:space:]]*[\(\[]([A-Z][a-z](,[A-Z][a-z])+)[\)\]]//g; s/[[:space:]]*[\(\[](Europe|USA?|Japan|Asia|World|PAL|NTSC|Rev[[:space:]]*[0-9]*)[\)\]]//gi; s/[[:space:]]+(PAL|NTSC|Europe|USA?|Japan|Asia|World)$//gi; s/[[:space:]]+/ /g; s/^ //; s/ $//' <<<"${1//_/ }"; }
set_reg() {
  ((!HAS_WIT)) && return
  local c
  c=$(wit dump -ll -- "$1" 2>/dev/null | awk -F': ' '/^Region\s*:/{print $2;exit}')
  [[ ${c^^} == "${WREG^^}" ]] || {
    log "Reg->$WREG: $1"
    run wit edit --region "$WREG" -q -- "$1"
  }
}
trim_game() {
  log "Trim: $1->$2"
  run wit copy --wbfs --trim --psel=data,-update -q -- "$1" "$2"
}
is_game() { [[ $1 =~ \.(wbfs|iso|ciso|wia|wdf)$ ]]; }
# --- Main Logic ---
proc_file() {
  local f=$1 id t n ndir ext dst
  is_game "${f,,}" || return
  if [[ ${f##*/} =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}
  else
    id=$(get_id "$f")
    [[ ${#id} -eq 6 ]] || {
      log "Skip(NoID): $f"
      return
    }
  fi
  t=$(get_title "$f")
  if [[ -n $t ]]; then
    n=$(clean "$t")
  else
    n=$(clean "${f##*/}")
    n=${n//\[$id\]/}
    n=${n%.*}
  fi
  n=$(sed 's/^\s*//;s/\s*$//' <<<"$n")
  [[ -n $n ]] || n="Unknown"
  ndir="$TGT/$n [$id]"
  ext=${f##*.}
  ext=${ext,,}
  dst="$ndir/$id.wbfs"
  if ((TRIM && HAS_WIT)); then
    run mkdir -p "$ndir"
    trim_game "$f" "$dst" && {
      set_reg "$dst"
      [[ $f -ef $dst ]] || run rm -f "$f"
    } || log "Trim Fail"
    return
  fi
  [[ $ext == wbfs && $f -ef $dst ]] && {
    set_reg "$f"
    return
  }
  run mkdir -p "$ndir"
  if ((CONV && HAS_WIT && ext != "wbfs")); then
    run wit copy --wbfs -q "$f" "$dst" && {
      set_reg "$dst"
      run rm -f "$f"
    } || {
      run mv -n "$f" "$ndir/$id.$ext"
      set_reg "$ndir/$id.$ext"
    }
  else
    run mv -n "$f" "$ndir/$id.$ext"
    set_reg "$ndir/$id.$ext"
  fi
}

proc_dir() {
  local d=$1 base=${d##*/} id g t n ndir f gid
  [[ $base =~ \[[A-Z0-9]{6}\] ]] && return
  for f in "$d"/*.{wbfs,iso,ciso,wia,wdf}; do
    [[ -f $f ]] || continue
    id=$(get_id "$f")
    [[ ${#id} -eq 6 ]] && {
      g=$f
      break
    }
  done
  [[ -z ${g:-} ]] && return
  t=$(get_title "$g")
  n=$(clean "${t:-$base}")
  [[ -n $n ]] || n="Unknown"
  ndir="$TGT/$n [$id]"
  [[ -d $ndir && ! $d -ef $ndir ]] && return
  [[ $d -ef $ndir ]] || {
    log "Dir: $d->$ndir"
    run mv -n "$d" "$ndir"
  }
  for f in "$ndir"/*.{wbfs,iso,ciso,wia,wdf}; do
    [[ -f $f ]] || continue
    gid=$(get_id "$f")
    [[ ${#gid} -eq 6 ]] || continue
    local dst="$ndir/$gid.wbfs" ext=${f##*.}
    ext=${ext,,}
    if ((TRIM && HAS_WIT)); then
      if [[ $f -ef $dst ]]; then
        trim_game "$f" "$ndir/.tmp_$gid" && {
          run mv -f "$ndir/.tmp_$gid" "$dst"
          set_reg "$dst"
        } || run rm -f "$ndir/.tmp_$gid"
      else trim_game "$f" "$dst" && {
        set_reg "$dst"
        run rm -f "$f"
      }; fi
    elif ((CONV && HAS_WIT && ext != "wbfs")); then
      run wit copy --wbfs -q "$f" "$dst" && {
        set_reg "$dst"
        run rm -f "$f"
      }
    elif [[ ${f##*/} != "$gid.$ext" ]]; then
      run mv -n "$f" "$ndir/$gid.$ext"
      set_reg "$ndir/$gid.$ext"
    else set_reg "$f"; fi
  done
}

# --- Exec ---
for x in "$TGT"/*; do
  [[ -f $x ]] && proc_file "$x"
  [[ -d $x ]] && proc_dir "$x"
done
log "Done"
