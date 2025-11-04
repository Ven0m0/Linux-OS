#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob
export LC_ALL=C LANG=C.UTF-8

has() { command -v -- "$1" &>/dev/null; }

sudo -v
sudo pacman -Syyuq --noconfirm --needed
sudo pacman-db-upgrade
has keyserver-rank && keyserver-rank --yes || :

export RATE_MIRRORS_PROTOCOL=https \
  RATE_MIRRORS_ALLOW_ROOT=true RATE_MIRRORS_DISABLE_COMMENTS_IN_FILE=true RATE_MIRRORS_DISABLE_COMMENTS=true \
  CONCURRENCY="$(nproc)" RATE_MIRRORS_ENTRY_COUNTRY="${RATE_MIRRORS_ENTRY_COUNTRY:-DE}"
MIRRORDIR=/etc/pacman.d
TMPFILE=$(mktemp)

mirroropt(){
  local name="$1" file="${2:-$MIRRORDIR/${1}-mirrorlist}"
  #sudo find -O2 /etc/pacman.d/ -name "*backup*" -type f --exec xargs -r sudo rm -f
  [[ -r $file ]] || { echo "Missing: $file" >&2; return 1; }
  echo "→ Ranking $name..."
  rate-mirrors stdin \
    --save="$TMPFILE" \
    --fetch-mirrors-timeout=300000 \
    --comment-prefix="# " \
    --output-prefix="Server = " \
    --path-to-return='$repo/os/$arch' \
    < <(grep -Eo 'https?://[^ ]+' "$file" | sort -u)
  install -m644 -b -S -T "$TMPFILE" "$file"
}

if has cachyos-rate-mirrors; then
  sudo cachyos-rate-mirrors
else
  mirroropt arch
  mirroropt cachyos
fi

for repo in chaotic-aur endeavouros alhp; do
  mirroropt "$repo"
done

chmod go+r "$MIRRORDIR"/*mirrorlist*
echo "✔ Updated all mirrorlists"
sudo pacman -Syyuq --noconfirm --needed
