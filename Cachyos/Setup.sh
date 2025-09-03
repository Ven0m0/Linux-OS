#!/usr/bin/env bash
export LC_ALL=C LANG=C.UTF-8
sudo -v
# --- CONFIG ---
DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git" # dotfiles repo
DOTFILES_TOOL="chezmoi"  # or "dotter"
# --- DETECT PACKAGE MANAGER ---
if command -v pacman &>/dev/null; then
    PKG='sudo pacman -Sy --needed --noconfirm'
    sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf
    sudo pacman -Syu --needed --noconfirm >/dev/null
elif command -v apt-get &>/dev/null; then
    PKG='sudo apt-get install -y'
    sudo apt-get update -y >/dev/null && sudo apt-get upgrade -y >/dev/null
else
    echo "No supported package manager found!"; exit 1
fi
# --- INSTALL DEPENDENCIES ---
echo "[*] Installing dependencies..."
eval "$PKG" "$DOTFILES_TOOL"
# --- CLONE DOTFILES & APPLY ---
echo "[*] Cloning and applying dotfiles..."
if [[ "$DOTFILES_TOOL" == "chezmoi" ]]; then
    chezmoi init "$DOTFILES_REPO"
    chezmoi apply -v
else
    git clone "$DOTFILES_REPO" "${HOME}/.dotfiles"
    cd -- "${HOME}/.dotfiles"
    dotter deploy
fi
echo "[*] Setup complete! All dotfiles and app configs restored."
