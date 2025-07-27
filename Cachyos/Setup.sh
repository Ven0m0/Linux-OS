#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

git clone git://github.com/Ven0m0/dotfiles $HOME/dotfiles

# --- CONFIG ---
DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git" # dotfiles repo
DOTFILES_TOOL="chezmoi"  # or "dotter"

# --- DETECT PACKAGE MANAGER ---
if command -v apt &>/dev/null; then
    PKG="sudo apt update && sudo apt install -y"
elif command -v pacman &>/dev/null; then
    PKG="sudo pacman -Sy --noconfirm"
else
    echo "No supported package manager found!"
    exit 1
fi

# --- INSTALL DEPENDENCIES ---
echo "[*] Installing dependencies..."
if [[ "$DOTFILES_TOOL" == "chezmoi" ]]; then
    $PKG chezmoi git
else
    $PKG dotter git
fi

# --- CLONE DOTFILES & APPLY ---
echo "[*] Cloning and applying dotfiles..."
if [[ "$DOTFILES_TOOL" == "chezmoi" ]]; then
    chezmoi init "$DOTFILES_REPO"
    chezmoi apply -v
else
    git clone "$DOTFILES_REPO" "$HOME/.dotfiles"
    cd "$HOME/.dotfiles"
    dotter deploy
fi

echo "[*] Setup complete! All dotfiles and app configs restored."
