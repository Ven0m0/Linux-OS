#!/usr/bin/env bash
export LC_ALL=C LANG=C
# Non destructive uutils-coreutils symlink script. Links it to an arbitrary bin folder in HOME
# Can easily be reverted unlike some other scripts that nuke your coreutils

#DEST="$HOME/bin/uutils"
DEST="$HOME/.local/bin"
PKG="uutils-coreutils"
SAFE_TOOLS=(
cat ls cp mv rm mkdir rmdir echo printf printenv env yes pwd dirname basename
touch stat dd du df head tail wc sort uniq cut tr fold split join
uname date id whoami groups true false test '[' sleep install more hostname
chown chmod dircolors ln kill nice nohup nproc fmt numfmt seq realpath readlink
users uptime tty who
)
mkdir -p "$DEST"
pacman -Qlq "$PKG" | grep '/bin/uu-' |
while read -r path; do
  bin=${path##*/}    # e.g. "uu-ls"
  name=${bin#uu-}    # → "ls"
  for safe in "${SAFE_TOOLS[@]}"; do
    if [[ $name == "$safe" ]]; then
      ln -snf -- "$path" "${DEST}/${name}"
    fi
  done
done
echo "Symlinked safe uutils into $DEST"
echo 'export PATH="${DEST}:${PATH}"'
echo 'or'
echo 'export PATH="${HOME}/.local/bin:${PATH}"'
