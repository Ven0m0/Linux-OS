#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
LC_ALL=C

has(){ command -v -- "$1" &>/dev/null; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }
log(){ ((VERB)) && printf '%s\n' "$@" >&2 || : ; }
run(){ ((DRY)) && log "[dry] $*" || "$@"; }

CONV=1 DRY=0 VERB=0 REGION=${WBFSMV_REGION:-PAL}
while [[ ${1:-} == -* ]]; do
  case $1 in
    -c|--convert) CONV=1 ;;
    --no-convert) CONV=0 ;;
    -n|--dry-run) DRY=1 ;;
    -v|--verbose) VERB=1 ;;
    -h|--help) printf 'Usage: %s [-c|-n|-v] [DIR]\n' "${0##*/}"; exit 0 ;;
    *) die "Err: $1" 2 ;;
  esac
  shift
done
TGT=${1:-.}
[[ -d $TGT ]] || die "No dir: $TGT" 2

has dd || die "Need dd" 1
HAS_WIT=0; has wit && HAS_WIT=1
((CONV && !HAS_WIT)) && die "Need wit for convert" 1

declare -rA RMAP=([PAL]=EUROPE [NTSC]=USA [JAP]=JAPAN [KOR]=KOREA [FREE]=FREE)
WREG=${RMAP[${REGION^^}]:-EUROPE}

get_id(){
  local f=$1 i s=0
  [[ ${f,,} == *.wbfs ]] && s=512
  ((HAS_WIT)) && i=$(wit ID6 -- "$f" 2>/dev/null | awk 'NR==1{print;exit}')
  [[ -z ${i:-} ]] && i=$(dd if="$f" bs=1 skip="$s" count=6 2>/dev/null | tr -dc 'A-Za-z0-9')
  echo "${i^^}"
}

get_title(){
  ((HAS_WIT)) && wit dump -ll -- "$1" 2>/dev/null | awk -F':  ' 'tolower($1)~/^(disc|game) title\s*$/{gsub(/^\s+|\s+$/,"",$2);print $2;exit}'
}

clean(){
  local s=${1//_/ }
  s=${s//\[([A-Z][a-z](,[A-Z][a-z])+)\]/}
  s=${s//\[Europe\]/}; s=${s//\[USA\]/}; s=${s//\[Japan\]/}; s=${s//\[Asia\]/}; s=${s//\[World\]/}; s=${s//\[PAL\]/}; s=${s//\[NTSC\]/}
  s=${s//\(Europe\)/}; s=${s//\(USA\)/}; s=${s//\(Japan\)/}; s=${s//\(Asia\)/}; s=${s//\(World\)/}; s=${s//\(PAL\)/}; s=${s//\(NTSC\)/}
  s=${s// PAL/}; s=${s// NTSC/}; s=${s// Europe/}; s=${s// USA/}; s=${s// Japan/}; s=${s// Asia/}; s=${s// World/}
  s=${s//  / }; s=${s# }; s=${s% }
  echo "$s"
}

set_reg(){
  ((! HAS_WIT)) && return
  local c
  c=$(wit dump -ll -- "$1" 2>/dev/null | awk -F': ' '/^Region\s*: /{print $2;exit}')
  [[ ${c^^} == "${WREG^^}" ]] && return
  log "Reg->$WREG: $1"
  run wit edit --region "$WREG" -q -- "$1"
}

is_game(){ [[ $1 =~ \.(wbfs|iso|ciso|wia|wdf)$ ]]; }

proc_file(){
  local f=$1 id t n ndir ext dst
  is_game "${f,,}" || return
  if [[ ${f##*/} =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}
  else
    id=$(get_id "$f")
    [[ ${#id} -eq 6 ]] || { log "Skip(NoID): $f"; return; }
  fi
  t=$(get_title "$f")
  n=$(clean "${t:-${f##*/}}")
  n=${n//\[$id\]/}; n=${n%.*}; n=${n# }; n=${n% }
  [[ -n $n ]] || n="Unknown"
  ndir="$TGT/$n [$id]"
  ext=${f##*.}; ext=${ext,,}
  dst="$ndir/$id. wbfs"
  [[ $ext == wbfs && $f -ef $dst ]] && { set_reg "$f"; return; }
  run mkdir -p "$ndir"
  if ((CONV && HAS_WIT && ext != "wbfs")); then
    run wit copy --wbfs -q "$f" "$dst" && { set_reg "$dst"; run rm -f "$f"; } || { run mv -n "$f" "$ndir/$id.$ext"; set_reg "$ndir/$id.$ext"; }
  else
    run mv -n "$f" "$ndir/$id.$ext"
    set_reg "$ndir/$id.$ext"
  fi
}

proc_dir(){
  local d=$1 base=${d##*/} id g t n ndir f gid
  [[ $base =~ \[[A-Z0-9]{6}\] ]] && return
  for f in "$d"/*. {wbfs,iso,ciso,wia,wdf}; do
    [[ -f $f ]] || continue
    id=$(get_id "$f")
    [[ ${#id} -eq 6 ]] && { g=$f; break; }
  done
  [[ -z ${g:-} ]] && return
  t=$(get_title "$g")
  n=$(clean "${t:-$base}")
  [[ -n $n ]] || n="Unknown"
  ndir="$TGT/$n [$id]"
  [[ -d $ndir && !  $d -ef $ndir ]] && return
  [[ $d -ef $ndir ]] || { log "Dir: $d->$ndir"; run mv -n "$d" "$ndir"; }
  for f in "$ndir"/*.{wbfs,iso,ciso,wia,wdf}; do
    [[ -f $f ]] || continue
    gid=$(get_id "$f")
    [[ ${#gid} -eq 6 ]] || continue
    local dst="$ndir/$gid. wbfs" ext=${f##*.}; ext=${ext,,}
    if ((CONV && HAS_WIT && ext != "wbfs")); then
      run wit copy --wbfs -q "$f" "$dst" && { set_reg "$dst"; run rm -f "$f"; }
    elif [[ ${f##*/} != "$gid.$ext" ]]; then
      run mv -n "$f" "$ndir/$gid.$ext"
      set_reg "$ndir/$gid.$ext"
    else
      set_reg "$f"
    fi
  done
}

for x in "$TGT"/*; do
  [[ -f $x ]] && proc_file "$x"
  [[ -d $x ]] && proc_dir "$x"
done
log "Done"
