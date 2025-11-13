#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1

# Initialize privilege tool
PRIV_CMD=$(init_priv)

# --- CONFIG ---
DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git" # dotfiles repo
DOTFILES_TOOL="chezmoi"                            # or "dotter"

# --- DETECT PACKAGE MANAGER ---
if has pacman; then
  PKG="run_priv pacman -Sy --needed --noconfirm"
  run_priv pacman -Syu --needed --noconfirm >/dev/null
elif has apt-get; then
  PKG="run_priv apt-get install -y"
  run_priv apt-get update -y >/dev/null && run_priv apt-get upgrade -y >/dev/null
else
  die "No supported package manager found!"
fi

# --- INSTALL DEPENDENCIES ---
log "Installing dependencies..."
eval "$PKG" "$DOTFILES_TOOL"

# --- CLONE DOTFILES & APPLY ---
log "Cloning and applying dotfiles..."
if [[ $DOTFILES_TOOL == "chezmoi" ]]; then
  chezmoi init "$DOTFILES_REPO"
  chezmoi apply -v
else
  git clone "$DOTFILES_REPO" "${HOME}/.dotfiles"
  cd -- "${HOME}/.dotfiles" || exit
  dotter deploy
fi

localectl set-locale C.UTF-8

log "*] Setup complete! All dotfiles and app configs restored."
run_priv sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf
run_priv sed -i 's/^#CleanMethod = KeepInstalled$/CleanMethod = KeepCurrent/' /etc/pacman.conf

run_priv pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
run_priv pacman --noconfirm --needed -U \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

cat <<'EOF' | run_priv tee -a /etc/pacman.conf >/dev/null
[artafinde]
Server = https://pkgbuild.com/~artafinde/repo
[endeavouros]
SigLevel = PackageRequired
Server = https://mirror.alpix.eu/endeavouros/repo/$repo/$arch
EOF

cat <<'EOF' | run_priv tee -a /etc/pacman.conf >/dev/null
[xyne-x86_64]
SigLevel = Required
Server = https://xyne.dev/repos/xyne
EOF

