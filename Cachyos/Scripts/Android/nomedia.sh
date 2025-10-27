#!/bin/sh
list_alldir() {
  for Dir in "$(ls -a "$1")"; do
    if [ "$Dir" != "." -a x"$Dir" != x".." ]; then
      if [[ -d "$1/$Dir" ]]; then
        echo "$1/$Dir"
        cd "$1/$Dir" || exit
        echo >>.nomedia
        cd ..
      fi
    fi
  done
}

list_alldir .

exit 0
