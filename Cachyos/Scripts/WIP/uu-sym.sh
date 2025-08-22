#!/usr/bin/env bash
export LC_ALL=C LANG=C
# Non destructive uutils-coreutils symlink script. Links it to an arbitrary bin folder in HOME
# Can easily be reverted unlike some other scripts that nuke your coreutils


DEST="$HOME/bin/uutils"
#DEST="$HOME/.local/bin"
PKG="uutils-coreutils"

SAFE_TOOLS=(
  cat ls cp mv rm mkdir rmdir echo printf yes pwd dirname basename
  touch stat du df head tail wc sort uniq cut tr fold split join
  uname date id whoami groups true false test sleep
)
mkdir -p "$DEST"
pacman -Qlq "$PKG" | grep '/bin/uu-' |
while read -r path; do
  bin=${path##*/}    # e.g. "uu-ls"
  name=${bin#uu-}    # → "ls"
  for safe in "${SAFE_TOOLS[@]}"; do
    if [[ $name == "$safe" ]]; then
      ln -sf "$path" "$DEST/$name"
    fi
  done
done
export PATH="$HOME/bin/uutils:$PATH"
echo "Symlinked safe uutils into $DEST"
echo "  export PATH=\"${DEST}:\$PATH\""
echo 'or'
echo "  export PATH=\"\$HOME/bin/uutils:\$PATH\""
