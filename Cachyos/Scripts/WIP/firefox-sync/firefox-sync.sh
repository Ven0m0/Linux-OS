#!/usr/bin/env bash
# Firefox profile sync to tmpfs for improved performance
set -euo pipefail

STATIC=main
LINK=
VOLATILE="/dev/shm/${USER}/firefox"

usage() {
  echo "Usage: firefox-sync [-dh] [-p profile-basename]"
}

longhelp() {
  usage
  cat <<EOF

This program syncs your firefox profile to a ramdisk (/dev/shm) and back.

-h prints this help message
-d prints the default profile directory
-p [dir] set the profile basename
-r restores on-disk profile (use only before uninstalling firefox-sync)
EOF
  exit 0
}

while getopts dhrp: options; do
  case $options in
    d) echo "default profile directory is ~/.mozilla/firefox/$LINK"
       exit 0;;
    h) longhelp;;
    p) LINK="$OPTARG";;
    r) if [[ -d "$VOLATILE" ]]; then
         mv "$VOLATILE" ~/.mozilla/firefox/"${LINK}"-copy
         mv ~/.mozilla/firefox/"${LINK}"{,-trash}
         mv ~/.mozilla/firefox/"${STATIC}"{,-trash}
         mv ~/.mozilla/firefox/"${LINK}"{-copy,}
         rm -rf ~/.mozilla/firefox/{"${LINK}","${STATIC}"}-trash
       else
         echo "Error: Volatile directory not found at $VOLATILE" >&2
         exit 1
       fi
       exit 0;;
    ?) usage
       exit 1;;
  esac
done

if [[ -z "$LINK" ]]; then
  echo "Error: Profile directory not set. Try the -p option" >&2
  exit 1
fi

[[ -r "$VOLATILE" ]] || install -dm700 "$VOLATILE"

cd ~/.mozilla/firefox || {
  echo "Error: ~/.mozilla/firefox does not exist" >&2
  exit 1
}

if [[ ! -e "$LINK" ]]; then
  echo "Error: ~/.mozilla/firefox/$LINK does not exist" >&2
  exit 1
fi

if [[ "$(readlink "$LINK")" != "$VOLATILE" ]]; then
  mv "$LINK" "$STATIC"
  ln -s "$VOLATILE" "$LINK"
fi

if [[ -e "$LINK/.unpacked" ]]; then
  rsync -av --delete --exclude .unpacked ./"$LINK"/ ./"$STATIC"/
else
  rsync -av ./"$STATIC"/ ./"$LINK"/
  touch "$LINK/.unpacked"
fi
