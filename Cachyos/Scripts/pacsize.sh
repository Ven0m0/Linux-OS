#!/usr/bin/env bash

# list pacman packages sorted by their "removable size".
#
# removable size is the space that will be freed up if
# you remove that package with `pacman -Rs <package>`.
#
# only explicitly installed packages are included.
#
# requires pacutils.

pacsize(){
  PAGER="${PAGER:-less}"
  if command -v pacinfo &>/dev/null; then
    pacman -Qqt | pacinfo --removable-size | awk '/^Name:/ { name = $2 } /^Installed Size:/ { size = $3$4 } /^$/ { print size" "name } ' | sort -uk2 | sort -rh | "$PAGER"
  else
    pacman -Qi | awk '/^Name/ {name=$3} /^Installed Size/ {print name, $4 substr($5,1,1)}' | column -t | sort -rhk2 | cat -n | tac
  fi
}
pacsize
