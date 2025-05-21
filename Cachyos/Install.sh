#!/usr/bin/env bash

sudo -v

sudo pacman -S bauh

# List of packages to install
packages=(
topgrade
bauh
partitionmanager
keyserver-rank-cachy
modprobed-db
rustup
llvm-bolt
openmp
polly
autofdo-bin
svgo
optipng
plasma-wayland-protocols
polkit-kde-agent
xorg-xhost
profile-sync-daemon
bleachbit
irqbalance
aria2
)

echo -e "\nInstalling packages: ${packages[*]}"
for pkg in "${packages[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    sudo pacman -S --noconfirm --needed "$pkg"
    echo "✔ Installed $pkg"
  else
    echo "✔ $pkg is already installed"
  fi
done

paru -S 
chaotic-keyring
chaotic-mirrorlist

cleanerml-git
alhp-keyring
alhp-mirrorlist
makepkg-optimize
