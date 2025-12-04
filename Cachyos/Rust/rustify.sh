#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sudo -v

# Optimization wrapper
cargo_install(){
  if command -v cargo-binstall &>/dev/null; then
    cargo binstall -y --locked "$@" || cargo install --locked "$@"
  else
    cargo install --locked "$@"
  fi
}

# Gnu utils
sudo pacman --needed --noconfirm -S uutils-coreutils
paru -S uutils-diffutils uutils-findutils uutils-procps-git
# Sed
paru -S uutils-sed-git
sudo pacman --needed --noconfirm -S sd
# Tar
sudo pacman --needed --noconfirm -Rns tar && paru -S uutils-tar-git
# Du
sudo pacman --needed --noconfirm -S dust
# Touch + mkdir
cargo install touchp
# Faster cp & rm
cargo install cpz rmz
# Grep
sudo pacman --needed --noconfirm -S ripgrep ripgrep-all repgrep
# Bash
sudo pacman --needed --noconfirm -S brush
# Find
sudo pacman --needed --noconfirm -S fd
# Cut
sudo pacman --needed --noconfirm -S hck
# Uniq
cargo install runiq
# Minify
cargo install minhtml
# Wget
cargo install kelpsget
# Update-alternatives for arch
sudo pacman --needed --noconfirm -S zenity
command -v update-alternatives &>/dev/null || cargo_install --git "https://github.com/fthomys/update-alternatives"
pbin="$(command -v update-alternatives || echo "$HOME"/.cargo/bin/update-alternatives)"
sudo ln -sf "$pbin" "/usr/local/bin/${pbin##*/}"
sudo tee "/etc/pacman.d/hooks/update-alternatives.hook" > /dev/null << 'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Path
Target = usr/bin/*
Target = usr/local/bin/*
Target = etc/alternatives/*

[Action]
Description = Rebuilding alternatives symlinks
When = PostTransaction
Exec = /usr/local/bin/update-alternatives sync
EOF

# dnsmasq / systemdresolved
# curl -sfL "https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Rust/etchdns.sh" | bash
# JQ
sudo pacman --needed --noconfirm -S jaq
# Stow alternatives:
# - https://github.com/RaphGL/Tuckr
# - https://github.com/levinion/stor
# Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
