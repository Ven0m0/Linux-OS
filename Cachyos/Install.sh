#!/usr/bin/env bash

sudo -v

echo "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"

echo "ranking mirrors"
sudo cachyos-rate-mirrors
sudo pacman -S keyserver-rank-cachy --noconfirm && sudo keyserver-rank --yes
sudo pacman -Syu --noconfirm

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' && sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# List of packages to install
packages=(
topgrade
bauh
partitionmanager
plasma-wayland-protocols
polkit-kde-agent
legcord
prismlauncher
obs-studio
#Dev
modprobed-db
rustup
curl-rustls
rust-bindgen
cargo-c
cargo-cache
cargo-machete
cargo-pgo
llvm-bolt
openmp
polly
mold
autofdo-bin
svgo
optipng
pigz
lbzip2
aria2
#Tweak
profile-sync-daemon
bleachbit
irqbalance
# mkinitcpio-firmware #Fix warning
xorg-xhost #Fixes sudo bash
libappindicator-gtk3  #Fixes blurry icons in Electron programs
appmenu-gtk-module #Fixes for GTK3 menus
xdg-desktop-portal #Kde file picker
cachyos-ksm-settings
)

echo -e "\nInstalling packages: ${packages[*]}"
for pkg in "${packages[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    sudo pacman -S --noconfirm "$pkg"
    echo "✔ Installed $pkg"
  else
    echo "✔ $pkg is already installed"
  fi
done

sudo pacman -S cpio bc --needed

packages1=(
cleanerml-git
#alhp-keyring
#alhp-mirrorlist
makepkg-optimize-mold
preload
#prelockd
precached
memavaild
uresourced
jdk24-graalvm-ee-bin
konsave
plzip
)

for aur_pkg in "${packages1[@]}"; do
  paru -S --noconfirm "$aur_pkg"
done

# Install Rust nightly toolchain with minimal profile
rustup toolchain uninstall nightly-x86_64-unknown-linux-gnu
rustup toolchain install nightly --profile minimal
rustup toolchain uninstall stable-x86_64-unknown-linux-gnu

# Add Rust components
rust=(
rust-src
llvm-tools-x86_64-unknown-linux-gnu
clippy-x86_64-unknown-linux-gnu
rustfmt-x86_64-unknown-linux-gnu
)

for rust_pkg in "${rust[@]}"; do
  rustup component add  "$rust_pkg"
done

rustup default nightly

# Debloat and fixup
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm
sudo pacman -Rns cachy-browser --noconfirm

sudo systemctl enable pci-latency.service
sudo systemctl enable fstrim.timer
# https://gist.github.com/dante-robinson/cd620c7283a6cc1fcdd97b2d139b72fa
sudo systemctl enable irqbalance
sudo systemctl enable memavaild
sudo systemctl enable preload
#sudo systemctl enable prelockd
sudo systemctl enable uresourced

sudo pacman -Syu --noconfirm
sudo topgrade -c --disable config_update --skip-notify -y
sudo pacman -Rns "$(pacman -Qtdq)" --noconfirm > /dev/null || true
flatpak uninstall --unused
sudo pacman -Scc --noconfirm && sudo paccache -rk0 -q
sudo fstrim -av --quiet-unsupported
rm -rf /var/cache/*
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
# Empty global trash
rm -rf ~/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*
# Clear user-specific cache
rm -rf ~/.cache/*
sudo rm -rf root/.cache/*
rm -f ~/.mozilla/firefox/Crash\ Reports/*
# Clear Flatpak cache
rm -rf ~/.var/app/*/cache/*
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf ~/.cache/flatpak/system-cache/*
rm -rf ~/.local/share/flatpak/system-cache/*
rm -rf ~/.var/app/*/data/Trash/*
# Clear system logs
sudo rm -f /var/log/pacman.log
sudo journalctl --vacuum-time=1s
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*
