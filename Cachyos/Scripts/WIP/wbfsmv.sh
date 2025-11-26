#!/usr/bin/env bash
set -uo pipefail; shopt -s nullglob dotglob
LC_ALL=C have_wit=0
command -v wit &>/dev/null && have_wit=1

# get 6-char ID from file (wbfs/iso/wia/ciso/whatever)
get_id_from_file() {
  local f=$1 id
  if ((have_wit)); then
    # wit ID6 prints the ID or nothing on error
    id=$(wit ID6 -- "$f" 2>/dev/null) || id=""
    id=${id%%$'\n'*}
  fi
  # offset 0x200 (512) 6 bytes, dd may produce NULs; strip them
  [[ -z $id ]] && id=$(dd if="$f" bs=1 skip=512 count=6 2>/dev/null | tr -d '\0' || true)
  printf '%s' "${id^^}" # uppercase
}
# normalize display name: replace _ and - with space, collapse spaces, trim
norm_name() {
  local s="$1"
  s=${s//_/ }
  s=${s//-/ }
  # collapse multiple spaces and trim
  printf '%s' "$s" | sed -E 's/  +/ /g; s/^ //; s/ $//'
}
# process files (wbfs/iso/etc)
for f in *; do
  [[ -f $f ]] || continue
  [[ $f == .* ]] && continue
  # if file already inside a correctly named dir, skip (we only handle top-level)
  # only handle wbfs/iso/ciso/wia/wdf etc — but check common extensions
  case "${f,,}" in
  *.wbfs | *.iso | *.ciso | *.wia | *.wdf) ;;
  *) continue ;;
  esac
  # if filename already contains [ID]
  if [[ $f =~ \[([A-Z0-9]{6})\] ]]; then
    id=${BASH_REMATCH[1]}
    name=${f//\[$id\]/}
    name=${name%.*}
    name=$(norm_name "$name")
  else
    id=$(get_id_from_file "$f")
    [[ ${#id} -eq 6 ]] || continue
    name=${f%.*}
    name=$(norm_name "$name")
  fi
  newdir="${name} [${id}]"
  mkdir -p -- "$newdir" &>/dev/null || :
  # move and rename to GAMEID.wbfs (keep extension wbfs if input was iso -> convert not attempted)
  mv -f -- "$f" "$newdir/${id}.wbfs" 2>/dev/null || mv -- "$f" "$newdir/${id}${f##*.}" 2>/dev/null || :
done
# process directories (try to read a .wbfs/.iso inside to get ID)
for d in *; do
  [[ -d $d ]] || continue
  # skip already-correct dirs
  [[ $d =~ \[[A-Z0-9]{6}\] ]] && continue
  # find candidate file inside (prefer wbfs then iso)
  id=""
  for ext in wbfs iso ciso wia wdf; do
    for g in "$d"/*."$ext"; do
      [[ -f $g ]] || continue
      id=$(get_id_from_file "$g")
      [[ ${#id} -eq 6 ]] && break 2
    done
  done
  # if not found, try first file in dir
  if [[ -z $id ]]; then
    for g in "$d"/*; do
      [[ -f $g ]] || continue
      id=$(get_id_from_file "$g")
      [[ ${#id} -eq 6 ]] && break
    done
  fi
  [[ ${#id} -eq 6 ]] || continue
  name=$(norm_name "$d")
  newdir="${name} [${id}]"
  # avoid clobbering existing correct dir
  [[ -e $newdir ]] && continue
  mv -f -- "$d" "$newdir" 2>/dev/null || :
done
