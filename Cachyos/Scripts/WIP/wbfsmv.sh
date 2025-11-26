#!/usr/bin/env bash
# wbfsmv.sh - move/rename Wii game files/dirs into "Game Name [GAMEID]/GAMEID.wbfs"
# Usage: bash wbfsmv.sh [-c|--convert] [target_dir]
# -c|--convert : use `wit copy --wbfs` to convert ISO-like files to GAMEID.wbfs
# Requires: wit (optional but recommended), dd, sed, awk
set -uo pipefail
shopt -s nullglob dotglob
LC_ALL=C
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

# get title from file via wit; fallback empty
get_title_from_file(){
  local f=$1 title
  [[ $have_wit -eq 1 ]] || { printf '' ; return; }
  # try different labels; take first non-empty
  title=$(wit dump -ll -- "$f" 2>/dev/null | awk -F': ' '
    /^Title[[:space:]]*:/ { if($2!="") {print $2; exit} }
    /^Disc Title[[:space:]]*:/ { if($2!="") {print $2; exit} }
    /^Game title[[:space:]]*:/ { if($2!="") {print $2; exit} }
  ')
  # trim
  printf '%s' "$(printf '%s' "$title" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
}

# clean: remove region/lang blocks like "(Europe)" or "(En,Fr,De,Es,It)" and other noisy tags
clean_name(){
  local s="$1"
  # normalize spaces around punctuation, remove underscores, collapse spaces
  s=${s//_/ } ; s=${s//\t/ } ; s=${s//  / }
  # remove parenthesis blocks that contain commas or region/lang keywords (case-insensitive)
  # GNU sed's I flag used for case-insensitive match
  s=$(printf '%s' "$s" \
    | sed -E 's/[[:space:]]*[\(\[][^)\]]*(,|Europe|PAL|NTSC|USA|US|Japan|Rev|En|Fr|De|Es|It|Ja|Ko|Nl|Pt|Ru|Cn|Ch|Aus)[^)\]]*[\)\]]//gI' \
    | sed -E 's/  +/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')
  # remove stray trailing hyphens or slashes
  s=$(printf '%s' "$s" | sed -E 's/[[:space:]]*[-\/]+[[:space:]]*$//')
  printf '%s' "$s"
}

# set region EUROPE/PAL in-place if not already; quiet; recursive flag harmless
region_fix_if_needed(){
  local f=$1 region
  [[ $have_wit -eq 1 ]] || return 0
  region=$(wit dump -ll -- "$f" 2>/dev/null | awk -F': ' '/Region/ {print $2; exit}')
  [[ -n $region ]] && [[ $region = "EUROPE" ]] && region=PAL
  if [[ -z $region || $region != PAL ]]; then
    wit ed --region EUROPE -ii -r -- "$f" &>/dev/null || :
  fi
}

exts="wbfs iso ciso wia wdf"

# iterate inside TARGET only (do not rename TARGET itself)
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
      # attempt to use title from file (preferred) else clean filename
      title=$(get_title_from_file "$entry")
      if [[ -n $title ]]; then
        name=$(clean_name "$title")
      else
        name=$(clean_name "$(basename -- "$entry")")
        # strip the [ID] we detected
        name=${name//\[$id\]/}
      fi
    else
      id=$(get_id_from_file "$entry")
      [[ ${#id} -eq 6 ]] || continue
      title=$(get_title_from_file "$entry")
      if [[ -n $title ]]; then
        name=$(clean_name "$title")
      else
        name=$(clean_name "$(basename -- "$entry")"); name=${name%.*}
      fi
    fi
    # ensure region set
    region_fix_if_needed "$entry"
    newdir="$TARGET/${name} [${id}]"
    mkdir -p -- "$newdir" &>/dev/null || :
    case "${entry,,}" in
      *.wbfs) mv -n -- "$entry" "$newdir/${id}.wbfs" 2>/dev/null || mv -- "$entry" "$newdir/${id}.wbfs" 2>/dev/null || : ;;
      *)
        if (( convert )) && (( have_wit )); then
          if wit copy --wbfs -- "$entry" "$newdir/${id}.wbfs" &>/dev/null; then
            mv -n -- "$entry" "$newdir/" 2>/dev/null || mv -- "$entry" "$newdir/" 2>/dev/null || :
          else
            mv -n -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || mv -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || :
          fi
        else
          mv -n -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || mv -- "$entry" "$newdir/${id}.${entry##*.}" 2>/dev/null || :
        fi ;;
        
    esac
    continue
  fi

  # ---- directories ----
  if [[ -d $entry ]]; then
    # skip if dir already contains [ID]
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
    # try to get title from discovered file
    if [[ -n $g ]]; then
      title=$(get_title_from_file "$g")
      if [[ -n $title ]]; then
        name=$(clean_name "$title")
      else
        name=$(clean_name "$(basename -- "$entry")")
      fi
      region_fix_if_needed "$g"
    else
      name=$(clean_name "$(basename -- "$entry")")
    fi

    newdir="$TARGET/${name} [${id}]"
    [[ -e $newdir ]] && continue
    mv -n -- "$entry" "$newdir" 2>/dev/null || mv -- "$entry" "$newdir" 2>/dev/null || :
  fi
done
