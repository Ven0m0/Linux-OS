#!/usr/bin/env bash
# Rename/move Wii game files into "Game Name [GAMEID]/GAMEID.wbfs"
# Usage: ./wbfsmv.sh [-c|--convert] [target_dir]
# -c|--convert : run `wit copy --wbfs` for ISO-like files
# By default processes entries *inside* target_dir (does NOT rename target_dir itself).

set -uo pipefail
shopt -s nullglob dotglob

convert=0
while (( $# )) && [[ $1 == -* ]]; do
  case $1 in
    -c|--convert) convert=1; shift ;;
    -*) printf 'Unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

TARGET=${1:-.}
[[ -d $TARGET ]] || { printf 'Target not a directory: %s\n' "$TARGET" >&2; exit 2; }

command -v dd >/dev/null 2>&1 || { printf 'dd missing\n' >&2; exit 1; }
command -v wit >/dev/null 2>&1 && have_wit=1 || have_wit=0

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

# normalize display name: input may be a basename or path
norm_name(){
  local s base
  base=$(basename -- "$1")
  s=${base%.*}
  s=${s//_/ } ; s=${s//-/ }
  printf '%s' "$s" | sed -E 's/  +/ /g; s/^ //; s/ $//'
}

# ensure region EUROPE/PAL via wit; callable with filename (full path)
region_fix_if_needed(){
  local f=$1 region
  [[ $have_wit -eq 1 ]] || return 0
  region=$(wit dump -ll -- "$f" 2>/dev/null | grep -m1 "Region" | awk '{print $3}' || true)
  [[ -n $region ]] && [[ $region = "EUROPE" ]] && region=PAL
  if [[ -z $region || $region != PAL ]]; then
    wit ed --region EUROPE -ii -r -- "$f" &>/dev/null || :
  fi
}

exts="wbfs iso ciso wia wdf"

# iterate entries inside TARGET (do not operate on TARGET itself)
for entry in "$TARGET"/*; do
  [[ -e $entry ]] || continue

  # ---- files ----
  if [[ -f $entry ]]; then
    case "${entry,,}" in
      *.wbfs|*.iso|*.ciso|*.wia|*.wdf) ;;
      *) continue ;;
    esac

    # if filename already contains [ID]
    if [[ $(basename -- "$entry") =~ \[([A-Z0-9]{6})\] ]]; then
      id=${BASH_REMATCH[1]}
      name=$(norm_name "$(basename -- "$entry")")
    else
      id=$(get_id_from_file "$entry")
      [[ ${#id} -eq 6 ]] || continue
      name=$(norm_name "$entry")
    fi

    region_fix_if_needed "$entry"

    newdir="$TARGET/${name} [${id}]"
    mkdir -p -- "$newdir" &>/dev/null || :

    case "${entry,,}" in
      *.wbfs)
        mv -n -- "$entry" "$newdir/${id}.wbfs" 2>/dev/null || mv -- "$entry" "$newdir/${id}.wbfs" 2>/dev/null || :
        ;;
      *)
        if (( convert )) && (( have_wit )); then
          if wit copy --wbfs -- "$entry" "$newdir/${id}.wbfs" &>/dev/null; then
            mv -n -- "$entry" "$newdir/" 2>/dev/null || mv -- "$entry" "$newdir/" 2>/dev/null || :
          else
            mv -n -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || mv -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || :
          fi
        else
          mv -n -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || mv -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || :
        fi
        ;;
    esac

    continue
  fi

  # ---- directories ----
  if [[ -d $entry ]]; then
    # skip if directory name already contains [ID]
    [[ $(basename -- "$entry") =~ \[[A-Z0-9]{6}\] ]] && continue

    id=; g=
    for e in $exts; do
      for candidate in "$entry"/*."$e"; do
        [[ -f $candidate ]] || continue
        id=$(get_id_from_file "$candidate")
        [[ ${#id} -eq 6 ]] && { g=$candidate; break 2; }
      done
    done

    if [[ -z $id ]]; then
      for candidate in "$entry"/*; do
        [[ -f $candidate ]] || continue
        id=$(get_id_from_file "$candidate")
        [[ ${#id} -eq 6 ]] && { g=$candidate; break; }
      done
    fi

    [[ ${#id} -eq 6 ]] || continue

    [[ -n $g ]] && region_fix_if_needed "$g"

    name=$(norm_name "$entry")
    newdir="$TARGET/${name} [${id}]"
    [[ -e $newdir ]] && continue
    mv -n -- "$entry" "$newdir" 2>/dev/null || mv -- "$entry" "$newdir" 2>/dev/null || :
  fi
done
