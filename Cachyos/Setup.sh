#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'

# Check if command exists
has(){ command -v "$1" &>/dev/null; }
log(){ printf '%b\n' "$*"; }
die(){ echo "Error: $*" >&2; exit 1; }
sudo -v

# --- CONFIG ---
DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git"
DOTFILES_TOOL="yadm"

# --- DETECT PACKAGE MANAGER ---
if has paru; then
  PKG="paru -S --needed --noconfirm"
  paru -Syu --needed --noconfirm --skipreview >/dev/null
elif has pacman; then
  PKG="sudo pacman -S --needed --noconfirm"
  sudo pacman -Syu --needed --noconfirm >/dev/null
elif has apt-get; then
  PKG="sudo apt-get install -y"
  sudo apt-get update -y >/dev/null; sudo apt-get upgrade -y >/dev/null
else
  die "No supported package manager found!"
fi

# --- INSTALL DEPENDENCIES ---
log "Installing dependencies..."
eval "$PKG" "$DOTFILES_TOOL"

# --- CLONE DOTFILES & APPLY ---
log "Cloning and applying dotfiles..."
if [[ $DOTFILES_TOOL == "yadm" ]]; then
  echo "TODO: yadm"
elif [[ $DOTFILES_TOOL == "chezmoi" ]]; then
  chezmoi init "$DOTFILES_REPO"
  chezmoi apply -v
else
  git clone "$DOTFILES_REPO" "${HOME}/.dotfiles"
  cd -- "${HOME}/.dotfiles" || exit
fi

localectl set-locale C.UTF-8
sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg
ssh-keyscan -H aur.archlinux.org >> ~/.ssh/known_hosts
ssh-keyscan -H github.com >> ~/.ssh/known_hosts
sudo chown -c root:root /etc/doas.conf; sudo chmod -c 0400 /etc/doas.conf

log "*] Setup complete! All dotfiles and app configs restored."
sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf
sudo sed -i 's/^#CleanMethod = KeepInstalled$/CleanMethod = KeepCurrent/' /etc/pacman.conf

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman --noconfirm --needed -U \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

cat <<'EOF' | sudo tee -a /etc/pacman.conf >/dev/null
[artafinde]
Server = https://pkgbuild.com/~artafinde/repo
[endeavouros]
SigLevel = PackageRequired
Server = https://mirror.alpix.eu/endeavouros/repo/$repo/$arch
EOF

cat <<'EOF' | sudo tee -a /etc/pacman.conf >/dev/null
[xyne-x86_64]
SigLevel = Required
Server = https://xyne.dev/repos/xyne
EOF

