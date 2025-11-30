#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

MIRRORDIR="/etc/pacman.d"
BACKUPDIR="$MIRRORDIR/.bak"
ARCHLIST_URL_GLOBAL="https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
ARCHLIST_URL_DE="https://archlinux.org/mirrorlist/?country=DE&protocol=https&ip_version=4&ip_version=6&use_mirror_status=on"
REPOS=(arch cachyos chaotic-aur endeavouros alhp)
DEFAULT_COUNTRY="DE"

_exists(){ command -v "$1" &>/dev/null; }

# Dialog selection logic
select_dialog(){
  if _exists yad; then
    yad --title="Mirrorlist Ranker" --width=400 --height=300 --form \
      --field="Mode:":CB "Temporary,Full-Interactive,Single Mirrorlist,Multi Mirrorlist" \
      --field="Mirrorlists:":CB "arch,cachyos,chaotic-aur,endeavouros,alhp" 2>/dev/null
  elif _exists gum; then
    gum choose "Temporary" "Full-Interactive" "Single Mirrorlist" "Multi Mirrorlist"
  else
    printf "Select mode:\n"; select m in Temporary Full-Interactive "Single Mirrorlist" "Multi Mirrorlist"; do
      echo "$m"; break
    done
  fi
}

pick_mirrorlist(){
  if _exists yad; then
    yad --list --title="Select Mirrorlist" --width=300 --height=200 --column="Mirrorlist" "${REPOS[@]}" 2>/dev/null
  elif _exists gum; then
    gum choose "${REPOS[@]}"
  elif _exists fzf; then
    printf "%s\n" "${REPOS[@]}" | fzf --prompt="Mirrorlist: "
  else
    printf "Mirrorlist:\n"; select ml in "${REPOS[@]}"; do
      echo "$ml"; break
    done
  fi
}

pick_multi_mirrorlists(){
  if _exists yad; then
    local opts=(); for r in "${REPOS[@]}"; do opts+=(FALSE "$r"); done
    yad --list --title="Select Mirrorlists" --multiple --separator=',' --checklist \
      --width=400 --height=250 --column="Select" --column="Mirrorlists" "${opts[@]}" 2>/dev/null | tr ',' '\n'
  elif _exists gum; then
    gum choose --no-limit "${REPOS[@]}"
  elif _exists fzf; then
    printf "%s\n" "${REPOS[@]}" | fzf -m --prompt="Mirrorlists: "
  else
    printf "Mirrorlists (space delimited): "; read -ra sels; printf "%s\n" "${sels[@]}"
  fi
}

backup(){
  [[ -f $1 ]] || return 0
  mkdir -p "$BACKUPDIR"
  cp -a "$1" "$BACKUPDIR/${1##*/}-$(date +%s).bak"
  find "$BACKUPDIR" -name "${1##*/}-*.bak" -printf '%T@ %p\n' | sort -rn | tail -n+6 | awk '{print $2}' | xargs -r rm -f
}

rank_archlist(){
  local url="$1" file="$MIRRORDIR/mirrorlist"
  local tmp; tmp=$(mktemp)
  curl -sfL "$url" -o "$tmp.mlst" || { rm -f "$tmp" "$tmp.mlst"; return 1; }
  sd -s '##\s*Server' 'Server' < "$tmp.mlst" > "$tmp.raw" || sed -E 's|^##[ ]*Server|Server|' "$tmp.mlst" > "$tmp.raw"
  rate-mirrors --save="$tmp" --entry-country="$DEFAULT_COUNTRY" --top-mirrors-number-to-retest=5 arch --file "$tmp.raw" &>/dev/null \
    || { rm -f "$tmp" "$tmp.mlst" "$tmp.raw"; return 1; }
  install -m644 "$tmp" "$file"; rm -f "$tmp" "$tmp.mlst" "$tmp.raw"
}

rank_repo(){
  local repo=$1 file="$MIRRORDIR/${repo}-mirrorlist"
  [[ -f $file ]] || return 0
  backup "$file"
  local tmp; tmp=$(mktemp)
  grep -oP 'https?://[^ ]+' "$file" | sort -u | rate-mirrors --save="$tmp" --entry-country="$DEFAULT_COUNTRY" stdin \
    --fetch-mirrors-timeout=5000 --path-to-return='$repo/os/$arch' &>/dev/null || { rm -f "$tmp"; return 1; }
  install -m644 "$tmp" "$file"; rm -f "$tmp"
}

main(){
  local choice mirrors
  choice=$(select_dialog)
  case $choice in
    *Temporary*)
      printf "Temporary mode: Will NOT overwrite existing mirrorlists!\n"
      mirrors=$(pick_multi_mirrorlists)
      for m in $mirrors; do
        if [[ $m == arch ]]; then
          rank_archlist "$ARCHLIST_URL_DE"
        else
          rank_repo "$m"
        fi
      done ;;
    *Single*)
      mirrors=$(pick_mirrorlist)
      [[ $mirrors == arch ]] && rank_archlist "$ARCHLIST_URL_DE" || rank_repo "$mirrors" ;;
    *Multi*)
      mirrors=$(pick_multi_mirrorlists)
      for m in $mirrors; do
        [[ $m == arch ]] && rank_archlist "$ARCHLIST_URL_DE" || rank_repo "$m"
      done ;;
    *)
      printf "Full interactive mode\n"
      mirrors=$(pick_multi_mirrorlists)
      for m in $mirrors; do
        [[ $m == arch ]] && rank_archlist "$ARCHLIST_URL_DE" || rank_repo "$m"
      done ;;
  esac
}

main "$@"
