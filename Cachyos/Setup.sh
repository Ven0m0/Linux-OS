#!/usr/bin/env bash
export LC_ALL=C LANG=C
sudo -v
# --- CONFIG ---
DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git" # dotfiles repo
DOTFILES_TOOL="chezmoi"                            # or "dotter"
# --- DETECT PACKAGE MANAGER ---
if command -v pacman &>/dev/null; then
  PKG='sudo pacman -Sy --needed --noconfirm'
  sudo pacman -Syu --needed --noconfirm >/dev/null
elif command -v apt-get &>/dev/null; then
  PKG='sudo apt-get install -y'
  sudo apt-get update -y >/dev/null && sudo apt-get upgrade -y >/dev/null
else
  echo "No supported package manager found!"
  exit 1
fi
# --- INSTALL DEPENDENCIES ---
echo "[*] Installing dependencies..."
eval "$PKG" "$DOTFILES_TOOL"
# --- CLONE DOTFILES & APPLY ---
echo "[*] Cloning and applying dotfiles..."
if [[ $DOTFILES_TOOL == "chezmoi" ]]; then
  chezmoi init "$DOTFILES_REPO"
  chezmoi apply -v
else
  git clone "$DOTFILES_REPO" "${HOME}/.dotfiles"
  cd -- "${HOME}/.dotfiles" || exit
  dotter deploy
fi

localectl set-locale C.UTF-8

echo "[*] Setup complete! All dotfiles and app configs restored."
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

## Improve NVME
if "$(find /sys/block/nvme[0-9]* | grep -q nvme)"; then
  echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
fi
