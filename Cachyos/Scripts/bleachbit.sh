#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Install BleachBit custom cleaners
paru --noconfirm --skipreview --needed -S bleachbit bleachbit-admin cleanerml-git xorg-xhost || :

src="${HOME}/.config/bleachbit/cleaners"
dsts=(/usr/share/bleachbit/cleaners /root/.config/bleachbit/cleaners)
[[ ! -d /usr/share/bleachbit ]] && {
  echo "/usr/share/bleachbit doesnt exist, install bleachbit first"
  exit 1
}
mkdir -p /root/.config/bleachbit/cleaners
mkdir -p "${HOME}/.config/bleachbit"
for dst in "${dsts[@]}"; do
  install -d "$dst" || :
  for file in "${src}"/*; do
    [[ -f $file ]] || continue
    fname="${file##*/}"
    ln -f "$file" "$dst/$fname" || :
  done
done

echo "done"
