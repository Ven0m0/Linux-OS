
pacman -Qlq uutils-coreutils | grep '/bin/uu-'
mkdir -p "$HOME/bin/uutils"

pacman -Qlq uu-coreutils | grep '/bin/uu-' |
while read -r path; do
  bin=${path##*/}         # e.g., "uu-ls"
  name=${bin#uu-}         # strip prefix → "ls"
  ln -sf "$path" "$HOME/bin/uutils/$name"
done
export PATH="$HOME/bin/uutils:$PATH"
ls --version | head -1
