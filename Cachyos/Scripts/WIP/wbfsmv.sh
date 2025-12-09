#!/usr/bin/env bash
# wbfsmv.sh - organize Wii games for USB Loader GX: "Game Name [GAMEID]/GAMEID.wbfs"
# Usage: wbfsmv.sh [-c|--convert] [-t|--trim] [-n|--dry-run] [-v|--verbose] [target_dir]
# Env: WBFSMV_REGION (default: PAL) - region to set (PAL|NTSC|JAP|KOR|FREE)
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C LANG=C

convert=0 trim=0 dry=0 verbose=0
REGION=${WBFSMV_REGION:-PAL}
while (($#)) && [[ $1 == -* ]]; do
  case $1 in
    -c | --convert) convert=1 ;;
    -t | --trim) trim=1 ;;
    -n | --dry-run) dry=1 ;;
    -v | --verbose) verbose=1 ;;
    -h | --help)
      cat << 'EOF'
Usage: wbfsmv.sh [-c|--convert] [-t|--trim] [-n|--dry-run] [-v|--verbose] [target_dir]
Options:
  -c, --convert   Convert ISO/CISO/WIA/WDF to WBFS (requires wit)
  -t, --trim      Trim/scrub games to reduce size (requires wit, safe for real hardware)
  -n, --dry-run   Show what would be done without making changes
  -v, --verbose   Print progress messages
Environment:
  WBFSMV_REGION   Region to set on games (PAL|NTSC|JAP|KOR|FREE) [default: PAL]
EOF
      exit 0
      ;;
    *)
      printf 'Unknown arg: %s\n' "$1">&2
      exit 2
      ;;
  esac
  shift
done

TARGET=${1:-.}
[[ -d $TARGET ]] || {
  printf 'Not a directory: %s\n' "$TARGET">&2
  exit 2
}
command -v dd &>/dev/null || {
  printf 'dd required\n'>&2
  exit 1
}
have_wit=0
command -v wit &>/dev/null && have_wit=1
((trim || convert)) && ((!have_wit)) && {
  printf 'wit required for --convert/--trim\n'>&2
  exit 1
}
# map region names to wit values
declare -A region_map=([PAL]=EUROPE [NTSC]=USA [JAP]=JAPAN [KOR]=KOREA [FREE]=FREE)
wit_region=${region_map[${REGION^^}]:-EUROPE}
log(){ ((verbose)) && printf '%s\n' "$*">&2 || :; }
run(){ ((dry)) && log "[dry] $*" || "$@"; }
# WBFS: ID at 0x200 (512); ISO/CISO/WIA/WDF: ID at 0x0
get_id(){
  local f="$1" id='' off=0
  [[ ${f,,} == *.wbfs ]] && off=512
  if ((have_wit)); then
    id=$(wit ID6 -- "$f" 2>/dev/null | head -n1) || id=
  fi
  [[ -z $id ]] && id=$(dd if="$f" bs=1 skip="$off" count=6 2>/dev/null | tr -dc 'A-Za-z0-9')
  printf '%s' "${id^^}"
}
get_title(){
  local f="$1"
  ((have_wit)) || return 0
  wit dump -ll -- "$f" 2>/dev/null | awk -F': ' '
    /^(Disc )?Title[[:space:]]*:/ && $2!="" {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}
    /^Game title[[:space:]]*:/ && $2!="" {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}
  '
}
clean(){
  local s=${1//_/ }
  s=${s// / }
  s=$(sed -E 's/[[:space:]]*\(([A-Z][a-z](,[A-Z][a-z])+)\)//g; s/[[:space:]]*\[([A-Z][a-z](,[A-Z][a-z])+)\]//g' <<< "$s")
  s=$(sed -E 's/[[:space:]]*[\(\[][^]\)]*(\bPAL\b|\bNTSC\b|\bEurope\b|\bUSA?\b|\bJapan\b|\bAsia\b|\bWorld\b|\bRev[[:space:]]*[0-9]*\b)[^]\)]*[\)\]]//gI' <<< "$s")
  s=$(sed -E 's/[[:space:]]*\((Europe|USA?|Japan|Asia|World|PAL|NTSC)\)//gI; s/[[:space:]]*\[(Europe|USA?|Japan|Asia|World|PAL|NTSC)\]//gI' <<< "$s")
  s=$(sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//; s/[[:space:]\/-]+$//' <<< "$s")
  printf '%s' "$s"
}
set_region(){
  local f="$1"
  ((have_wit)) || return 0
  local cur
  cur=$(wit dump -ll -- "$f" 2>/dev/null | awk -F': ' '/^Region[[:space:]]*:/{print $2; exit}')
  [[ ${cur^^} == "${wit_region^^}" ]] && return 0
  log "set region $wit_region: $f"
  run wit edit --region "$wit_region" -q -- "$f" || :
}
# trim: remove unused blocks + update partition (safe for real hardware)
trim_game(){
  local src="$1" dst="$2"
  log "trim: $src -> $dst"
  # --psel=data,-update keeps game data, removes update partition (safe)
  # --trim removes unused sectors
  run wit copy --wbfs --trim --psel=data,-update -q -- "$src" "$dst"
}
exts=(wbfs iso ciso wia wdf)
is_game_ext(){
  local f=${1,,}
  for e in "${exts[@]}"; do [[ $f == *."$e" ]] && return 0; done
  return 1
}
process_file(){
  local f="$1" id title name newdir ext base
  is_game_ext "$f" || return 0
  base=${f##*/}
  if [[ $base =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}
  else
    id=$(get_id "$f")
    [[ ${#id} -eq 6 ]] || {
      log "skip (no ID): $f"
      return 0
    }
  fi
  title=$(get_title "$f")
  if [[ -n $title ]]; then
    name=$(clean "$title")
  else
    name=$(clean "${base%.*}")
    name=${name//\[$id\]/}
    name=$(sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' <<< "$name")
  fi
  [[ -n $name ]] || name="Unknown"
  newdir="$TARGET/${name} [${id}]"
  ext=${f##*.}
  ext=${ext,,}
  local dest="$newdir/${id}.wbfs"
  # check if already correct
  if [[ $ext == wbfs ]] && [[ $f -ef $dest ]] 2>/dev/null && ((!trim)); then
    set_region "$f"
    log "skip (already ok): $f"
    return 0
  fi
  log "file: $f -> $dest"
  run mkdir -p -- "$newdir"
  if ((trim)) && ((have_wit)); then
    # trim always outputs wbfs
    if trim_game "$f" "$dest"; then
      set_region "$dest"
      [[ $f -ef $dest ]] 2>/dev/null || {
        log "removing original: $f"
        run rm -f -- "$f"
      }
    else
      log "trim failed, moving as-is"
      run mv -n -- "$f" "$newdir/${id}.${ext}"
      set_region "$newdir/${id}.${ext}"
    fi
  elif ((convert)) && [[ $ext != wbfs ]] && ((have_wit)); then
    if run wit copy --wbfs -q -- "$f" "$dest"; then
      set_region "$dest"
      log "converted, removing original: $f"
      run rm -f -- "$f"
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
  local d=$1 id='' g='' title name newdir
  local base=${d##*/}
  [[ $base =~ \[[A-Z0-9]{6}\] ]] && {
    log "skip (already tagged): $d"
    return 0
  }
  for e in "${exts[@]}"; do
    for cand in "$d"/*."$e"; do
      [[ -f $cand ]] || continue
      id=$(get_id "$cand")
      [[ ${#id} -eq 6 ]] && {
        g="$cand"
        break 2
      }
    done
  done
  [[ ${#id} -eq 6 ]] || {
    log "skip (no game found): $d"
    return 0
  }
  title=$(get_title "$g")
  name=$(clean "${title:-$base}")
  [[ -n $name ]] || name="Unknown"
  newdir="$TARGET/${name} [${id}]"
  [[ $d -ef $newdir ]] 2>/dev/null && ((!trim)) && {
    log "skip (already ok): $d"
    return 0
  }
  if [[ -e $newdir ]] && ! [[ $d -ef $newdir ]]; then
    log "skip (target exists): $newdir"
    return 0
  fi
  # rename dir first
  if ! [[ $d -ef $newdir ]]; then
    log "dir: $d -> $newdir"
    run mv -n -- "$d" "$newdir"
  fi
  # process files inside (trim/convert/rename + set region)
  for e in "${exts[@]}"; do
    for gf in "$newdir"/*."$e"; do
      [[ -f $gf ]] || continue
      local gid gbase gext gdest
      gid=$(get_id "$gf")
      [[ ${#gid} -eq 6 ]] || continue
      gbase=${gf##*/}
      gext=${gf##*.}
      gext=${gext,,}
      gdest="$newdir/${gid}.wbfs"
      if ((trim)) && ((have_wit)); then
        if [[ $gf -ef $gdest ]] 2>/dev/null; then
          # in-place trim: use temp file
          local tmp="$newdir/.trim_tmp_${gid}.wbfs"
          if trim_game "$gf" "$tmp"; then
            run mv -f -- "$tmp" "$gdest"
            set_region "$gdest"
          else
            run rm -f -- "$tmp" || :
          fi
        else
          if trim_game "$gf" "$gdest"; then
            set_region "$gdest"
            run rm -f -- "$gf"
          fi
        fi
      elif ((convert)) && [[ $gext != wbfs ]] && ((have_wit)); then
        if run wit copy --wbfs -q -- "$gf" "$gdest"; then
          set_region "$gdest"
          run rm -f -- "$gf"
        fi
      elif [[ $gbase != "${gid}.${gext}" ]]; then
        run mv -n -- "$gf" "$newdir/${gid}.${gext}"
        set_region "$newdir/${gid}.${gext}"
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
