#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
has() { command -v "$1" &> /dev/null; }
log() { printf '%b\n' "$*"; }
die() {
  echo "Error: $*" >&2
  exit 1
}
sudo -v

DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git"
DOTFILES_TOOL="yadm"

if has paru; then
  PKG="paru -S --needed --noconfirm"
  paru -Syu --needed --noconfirm --skipreview &> /dev/null
elif has pacman; then
  PKG="sudo pacman -S --needed --noconfirm"
  sudo pacman -Syu --needed --noconfirm &> /dev/null
elif has apt-get; then
  PKG="sudo apt-get install -y"
  sudo apt-get update -y &> /dev/null && sudo apt-get upgrade -y &> /dev/null
else
  die "No supported package manager found!"
fi

log "Installing $DOTFILES_TOOL & applying dotfiles..."
eval "$PKG" "$DOTFILES_TOOL"

case $DOTFILES_TOOL in
yadm) yadm clone "$DOTFILES_REPO" && yadm bootstrap 2> /dev/null || : ;;
chezmoi) chezmoi init "$DOTFILES_REPO" && chezmoi apply -v ;;
*) git clone "$DOTFILES_REPO" "${HOME}/.dotfiles" && cd "${HOME}/.dotfiles" || exit ;;
esac

localectl set-locale C.UTF-8
sudo chmod -R 700 ~/.{ssh,gnupg}
ssh-keyscan -H {aur.archlinux.org,github.com} >> ~/.ssh/known_hosts 2> /dev/null
[[ -f /etc/doas.conf ]] && sudo chown root:root /etc/doas.conf && sudo chmod 0400 /etc/doas.conf

sudo ufw default allow outgoing
# Allow ports for LocalSend
sudo ufw allow 53317/udp
sudo ufw allow 53317/tcp
# Allow Docker containers to use DNS on host
sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'

log "Setup complete!"
sudo sed -i -e s'/\#LogFile.*/LogFile = /'g -e 's/^#CleanMethod = KeepInstalled$/CleanMethod = KeepCurrent/' /etc/pacman.conf

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman --noconfirm --needed -U \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

cat << 'EOF' | sudo tee -a /etc/pacman.conf > /dev/null
[artafinde]
Server = https://pkgbuild.com/~artafinde/repo
[endeavouros]
SigLevel = PackageRequired
Server = https://mirror.alpix.eu/endeavouros/repo/$repo/$arch
EOF

cat << 'EOF' | sudo tee -a /etc/pacman.conf > /dev/null
[xyne-x86_64]
SigLevel = Required
Server = https://xyne.dev/repos/xyne
EOF
