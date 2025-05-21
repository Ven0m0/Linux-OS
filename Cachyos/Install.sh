#!/usr/bin/env bash

sudo -v

sudo cachyos-rate-mirrors
sudo pacman -S keyserver-rank-cachy
sudo keyserver-rank --yes


# List of packages to install
packages=(
topgrade
bauh
partitionmanager
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
winesync-udev-rule
legcord
vkd3d
obs-studio
mkinitcpio-firmware
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


rustup toolchain install nightly --profile minimal
rustup component add rust-src
rustup component add llvm-tools-x86_64-unknown-linux-gnu
rustup component add rust-std-x86_64-unknown-linux-musl
rustup component add rustfmt-x86_64-unknown-linux-gnu
rustup component add rustc-dev-x86_64-unknown-linux-gnu

sudo pacman -Rns cachyos-v4-mirrorlist
sudo pacman -Rns cachy-browser


sudo systemctl enable fstrim.timer
sudo pacman -Syyu --noconfirm
sudo topgrade -c --disable config_update --skip-notify -y
