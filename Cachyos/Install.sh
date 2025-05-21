#!/usr/bin/env bash

sudo -v

sudo cachyos-rate-mirrors
sudo pacman -S keyserver-rank-cachy && sudo keyserver-rank --yes
sudo pacman -Syu --noconfirm

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' && sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

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
legcord
vkd3d
vkbasalt
obs-studio
mkinitcpio-firmware
prismlauncher
jre-openjdk
appmenu-gtk-module
libappindicator-gtk3  #Fixes blurry icons in Electron programs
xdg-desktop-portal #Kde file picker
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


packages1=(
cleanerml-git
alhp-keyring
alhp-mirrorlist
makepkg-optimize
preload
prelockd
jdk24-graalvm-ee-bin
precached
konsave
)

for aur_pkg in "${packages1[@]}"; do
  paru -S --noconfirm "$aur_pkg"
done

# Install Rust nightly toolchain with minimal profile
rustup toolchain install nightly --profile minimal

# Add Rust components
rust=(
rust-src
llvm-tools-x86_64-unknown-linux-gnu
rust-std-x86_64-unknown-linux-musl
rustfmt-x86_64-unknown-linux-gnu
rustc-dev-x86_64-unknown-linux-gnu
)

for rust_pkg in "${rust[@]}"; do
  rustup component add  "$rust_pkg"
done

# Debloat and fixup
sudo pacman -Rns cachyos-v4-mirrorlist
sudo pacman -Rns cachy-browser


sudo systemctl enable fstrim.timer

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
