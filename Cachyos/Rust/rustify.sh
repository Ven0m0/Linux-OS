#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sudo -v

# Gnu utils
sudo pacman -S uutils-coreutils
paru -S uutils-diffutils uutils-findutils uutils-procps-git 
# Sed
paru -S uutils-sed-git
sudo pacman -S sd
# Tar
sudo pacman -Rns tar && paru -S uutils-tar-git
# Du
sudo pacman -S dust
# Touch + mkdir
cargo install touchp
# Faster cp & rm
cargo install cpz rmz
# Grep
sudo pacman -S ripgrep ripgrep-all repgrep
# Bash
sudo pacman -S brush
# Find
sudo pacman -S fd
# Cut
sudo pacman -S hck
# Uniq
cargo install runiq
# Minify
cargo install minhtml
# Wget
cargo install kelpsget
# Update-alternatives for arch
sudo pacman -S zenity --noconfirm --needed
cargo install --git "https://github.com/fthomys/update-alternatives"
pbin="$(command -v update-alternatives || echo ${HOME}/.cargo/bin/update-alternatives)"
sudo ln -sf "$pbin" "/usr/local/bin/$(basename $pbin)"
# oxidizr-arch (switch to uutils, sudo-rs)
paru -S oxidizr-arch
# dnsmasq / systemdresolved
curl -sf "https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Rust/etchdns.sh" | bash
#
