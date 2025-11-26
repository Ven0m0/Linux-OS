#!/usr/bin/env bash
# Rename/move Wii game files into "Game Name [GAMEID]/GAMEID.wbfs"
# - supports .wbfs .iso .ciso .wia .wdf
# - optional conversion: --convert / -c  (uses wit copy --wbfs)
# - patches region to EUROPE in-place when needed (wit ed --region EUROPE -ii -r)
# Usage: ./wbfsmv.sh [-c|--convert]
set -uo pipefail
shopt -s nullglob dotglob
convert=0
while (( $# )); do
  case $1 in
    -c|--convert) convert=1; shift ;;
    -*) printf 'Unknown arg: %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done
command -v dd &>/dev/null || { printf 'dd missing\n' >&2; exit 1; }
command -v wit &>/dev/null && have_wit=1 || have_wit=0
# read 6-byte ID at offset 0x200 (512) or via wit ID6
get_id_from_file(){
  local f=$1 id
  if (( have_wit )); then
    id=$(wit ID6 -- "$f" 2>/dev/null) || id=
    id=${id%%$'\n'*}
  fi
  if [[ -z $id ]]; then
    id=$(dd if="$f" bs=1 skip=512 count=6 2>/dev/null | tr -d '\0' || true)
  fi
  printf '%s' "${id^^}"
}
# normalize display name: replace _ and - with space, collapse spaces, trim
norm_name(){
  local s=$1
  s=${s//_/ } ; s=${s//-/ }
  # collapse multi spaces and trim
  printf '%s' "$s" | sed -E 's/  +/ /g; s/^ //; s/ $//'
}
# ensure region EUROPE/PAL via wit; callable with filename
region_fix_if_needed(){
  local f=$1 region
  [[ $have_wit -eq 1 ]] || return 0
  region=$(wit dump -ll -- "$f" 2>/dev/null | grep -m1 "Region" | awk '{print $3}' || true)
  [[ -n $region ]] && [[ $region = "EUROPE" ]] && region=PAL
  if [[ -z $region || $region != PAL ]]; then
    # edit in-place, recursive flag harmless; ignore non-critical errors
    wit ed --region EUROPE -ii -r -- "$f" &>/dev/null || :
  fi
}
exts="wbfs iso ciso wia wdf"
# ---- handle top-level files ----
for f in *; do
  [[ -f $f ]] || continue
  [[ $f = .* ]] && continue
  case "${f,,}" in
    *.wbfs|*.iso|*.ciso|*.wia|*.wdf) ;;
    *) continue ;;
  esac
  if [[ $f =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}; name=${f//\[$id\]/}
    name=${name%.*}; name=$(norm_name "$name")
  else
    id=$(get_id_from_file "$f")
    [[ ${#id} -eq 6 ]] || continue
    name=${f%.*}
    name=$(norm_name "$name")
  fi
  # region fix before conversion/move
  region_fix_if_needed "$f"
  newdir="${name} [${id}]"
  mkdir -p -- "$newdir" &>/dev/null || :
  case "${f,,}" in
    *.wbfs)
      # already wbfs: just move and rename to GAMEID.wbfs
      mv -n -- "$f" "$newdir/${id}.wbfs" 2>/dev/null || mv -- "$f" "$newdir/${id}.wbfs" 2>/dev/null || :
      ;;
    *)
      if (( convert )) && (( have_wit )); then
        # try conversion to wbfs; quiet, move original as backup on success
        if wit copy --wbfs -- "$f" "$newdir/${id}.wbfs" &>/dev/null; then
          mv -n -- "$f" "$newdir/" 2>/dev/null || mv -- "$f" "$newdir/" 2>/dev/null || :
        else
          # conversion failed -> move original into dir, keep ext
          mv -n -- "$f" "$newdir/${id}.${f##*.}" 2>/dev/null || mv -- "$f" "$newdir/${id}.${f##*.}" 2>/dev/null || :
        fi
      else
        mv -n -- "$f" "$newdir/${id}.${f##*.}" 2>/dev/null || mv -- "$f" "$newdir/${id}.${f##*.}" 2>/dev/null || :
      fi
      ;;
  esac
done
# ---- handle top-level directories ----
for d in *; do
  [[ -d $d ]] || continue
  [[ $d =~ \[[A-Z0-9]{6}\] ]] && continue
  id="" g=""
  for e in $exts; do
    for candidate in "$d"/*."$e"; do
      [[ -f $candidate ]] || continue
      id=$(get_id_from_file "$candidate")
      [[ ${#id} -eq 6 ]] && { g=$candidate; break 2; }
    done
  done
  if [[ -z $id ]]; then
    for candidate in "$d"/*; do
      [[ -f $candidate ]] || continue
      id=$(get_id_from_file "$candidate")
      [[ ${#id} -eq 6 ]] && { g=$candidate; break; }
    done
  fi
  [[ ${#id} -eq 6 ]] || continue
  # attempt region fix on discovered file inside dir (no conversion inside dirs)
  [[ -n $g ]] && region_fix_if_needed "$g"
  name=$(norm_name "$d")
  newdir="${name} [${id}]"
  [[ -e $newdir ]] && continue
  mv -n -- "$d" "$newdir" 2>/dev/null || mv -- "$d" "$newdir" 2>/dev/null || :
done
