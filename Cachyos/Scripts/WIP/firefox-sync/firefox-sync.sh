#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'

readonly STATIC=main
readonly VOLATILE="/dev/shm/${USER}/firefox"
LINK=

detect_profile(){
  local profiles
  mapfile -t profiles < <(find -H ~/.mozilla/firefox -maxdepth 1 -type d -name "*.default*" -printf "%f\n")
  case ${#profiles[@]} in
    0) printf 'Error: No Firefox profile found\n' >&2; exit 1 ;;
    1) LINK=${profiles[0]} ;;
    *) printf 'Multiple profiles found. Use -p:\n' >&2
       printf '  %s\n' "${profiles[@]}" >&2; exit 1 ;;
  esac
}

usage(){ printf 'Usage: firefox-sync [-dhrp profile]\n'; }

longhelp(){
  usage
  cat << 'HELP'

Syncs Firefox profile to tmpfs (/dev/shm) for improved performance.

-d  Print default profile directory
-h  Print this help
-p  Set profile basename (auto-detects if single profile exists)
-r  Restore on-disk profile (use before uninstall)
HELP
  exit 0
}

while getopts dhrp: opt; do
  case $opt in
    d) [[ -z $LINK ]] && detect_profile
       printf 'Default: ~/.mozilla/firefox/%s\n' "$LINK"; exit 0 ;;
    h) longhelp ;;
    p) LINK=$OPTARG ;;
    r) [[ ! -d $VOLATILE ]] && {
         printf 'Error: Volatile dir not found: %s\n' "$VOLATILE" >&2; exit 1
       }
       cd ~/.mozilla/firefox || exit 1
       [[ -L $LINK ]] && rm "$LINK"
       [[ -d $STATIC ]] && mv "$STATIC" "$LINK"
       exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

[[ -z $LINK ]] && detect_profile
[[ -d $VOLATILE ]] || install -dm700 "$VOLATILE"

cd ~/.mozilla/firefox || { printf 'Error: ~/.mozilla/firefox missing\n' >&2; exit 1; }
[[ ! -e $LINK ]] && { printf 'Error: Profile not found: %s\n' "$LINK" >&2; exit 1; }

if [[ ! -L $LINK || $(readlink "$LINK") != "$VOLATILE" ]]; then
  [[ ! -L $LINK ]] && mv "$LINK" "$STATIC"
  ln -sf "$VOLATILE" "$LINK"
fi

if [[ -e $LINK/.unpacked ]]; then
  rsync -aq --delete-before --exclude=.unpacked "$LINK"/ "$STATIC"/
else
  rsync -aq "$STATIC"/ "$LINK"/
  touch "$LINK/.unpacked"
fi
