#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
export LC_ALL=C LANG=C.UTF-8 LANGUAGE=C
has(){ command -v -- "$1" &>/dev/null; }

sudo -v
sudo pacman -Syyuq --noconfirm --needed
sudo pacman-db-upgrade
has keyserver-rank && keyserver-rank --yes
export RATE_MIRRORS_PROTOCOL=https CONCURRENCY="$(nproc)" RATE_MIRRORS_ENTRY_COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-DE} RATE_MIRRORS_ALLOW_ROOT=true \
  RATE_MIRRORS_DISABLE_COMMENTS_IN_FILE=true RATE_MIRRORS_DISABLE_COMMENTS=true
declare -r MIRRORDIR="/etc/pacman.d"

mirroropt(){
  local repo="$1" path="$2"
  local mirrorlist="${2:-${MIRROR_DIR}/${1}-mirrorlist}"
  declare -r TMPFILE="$(mktemp)"
  if [[ -f $repo && ! $repo == stdin ]]; then
    rate-mirrors "$1" --save "$TMPFILE" --fetch-mirrors-timeout=300000
    cp -f --backup=simple --suffix="-backup" "${TMPFILE}" "$mirrorlist"
  elif [[ $repo == stdin ]]; then
    cat -s "$mirrorlist" | sort -u | rate-mirrors stdin --save="$TMPFILE" --fetch-mirrors-timeout=300000
       --path-to-return='$repo/os/$arch' \
       --comment-prefix="# " \
       --output-prefix="Server = "
    cp -f --backup=simple --suffix="-backup" "${TMPFILE}" "$mirrorlist"
  else
    echo "Mirrorlist not found, install PKG $(pacman -Fq "$path" 2>/dev/null || echo "that contains $path")"; exit 1
  fi
}
if has cachyos-rate-mirrors; then
  sudo cachyos-rate-mirrors
else
  mirroropt arch
  mirroropt cachyos
fi
mirroropt chaotic-aur
mirroropt endeavouros
mirroropt alhp alhp-mirrorlist

# TODO: maybe alternative
#reflector --save "$TMPFILE" -c "DE,*" -f -a 24 -p https --ipv4 --sort score #--sort rate

chmod go+r "${MIRROR_DIR}"/*mirrorlist*
echo "✔ Updated mirrorlists"
sudo pacman -Syyuq --noconfirm --needed
