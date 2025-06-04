#!/bin/bash

sudo -v

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
# Dev
pigz
lbzip2
lzlib
lrzip
minizip-ng
optipng
svgo
yasm
ccache
sccache
memcached
llvm-bolt
openmp
polly
mold
autofdo-bin
rustup
rust-bindgen
cbindgen
cargo-c
cargo-cache
cargo-machete
cargo-pgo
patchelf
patchutils
vulkan-mesa-layers
plasma-wayland-protocols
libvdpau-va-gl
vkd3d-proton-git
protonup-qt
protonplus
proton-ge-custom
vkbasalt
#Tweak
aria2
curl-rustls
librustls
menu-cache
profile-sync-daemon
profile-cleaner
bleachbit-git
irqbalance
# mkinitcpio-firmware #Fix warning
xorg-xhost #Fixes sudo bash
libappindicator-gtk3  #Fixes blurry icons in Electron programs
appmenu-gtk-module #Fixes for GTK3 menus
xdg-desktop-portal #Kde file picker
sudo-rs
modprobed-db
cachyos-ksm-settings
thefuck
cpupower-gui
openrgb
dropbear
optiimage
)

echo -e "\nInstalling packages: ${packages[*]}"
for pkg in "${packages[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    sudo pacman -S --noconfirm "$pkg" || true
    echo "✔ Installed $pkg"
  else
    echo "✔ $pkg is already installed"
  fi
done

sudo pacman -S cpio bc --needed || true

aur-pkgs=(
cleanerml-git
#alhp-keyring
#alhp-mirrorlist
makepkg-optimize-mold
preload
prelockd
precached
memavaild
uresourced
jdk24-graalvm-ee-bin
konsave
plzip
plzip-lzip-link
usb-dirty-pages-udev
pacman-accel-git
cleanlib32
optipng-parallel
dxvk-gplasync-bin
#pacman-parallelizer
)

for aur_pkg in "${aur-pkgs[@]}"; do
  paru -S --noconfirm "$aur_pkg" || true
done

# Install Rust nightly toolchain with minimal profile
# rustup toolchain uninstall nightly-x86_64-unknown-linux-gnu
# rustup toolchain install nightly --profile minimal
rustup toolchain install stable --profile minimal
# rustup toolchain uninstall stable-x86_64-unknown-linux-gnu

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

# rustup default nightly
rustup default stable

echo "Installing rust aur packages"

apprs=(
rust-css-minifier-git
rust-parallel
async
)

for rs_pkg in "${apprs[@]}"; do
  sudo paru -S --noconfirm "$rs_pkg"
done


# Better ssl
sudo pacman -S wolfssl --noconfirm
sudo ln -sf /usr/include/wolfssl/openssl /usr/include/openssl
sudo ln -sf /usr/lib/libwolfssl.so /usr/lib/libssl.so
sudo ln -sf /usr/lib/libwolfssl.so /usr/lib/libcrypto.so

# Image downloads
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PinkLady.webp -o $HOME/Pictures//PinkLady.webp
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PFP.webp -o $HOME/Pictures/PFP.web


echo "Installing gaming applications"
sudo pacman -S cachyos-gaming-meta cachyos-gaming-applications --noconfirm

echo "Debloat and fixup"
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm || true
sudo pacman -Rns cachy-browser --noconfirm || true
sudo systemctl enable pci-latency.service
sudo systemctl enable fstrim.timer
# https://gist.github.com/dante-robinson/cd620c7283a6cc1fcdd97b2d139b72fa
sudo systemctl enable irqbalance
sudo systemctl enable memavaild
sudo systemctl enable preload
sudo systemctl enable prelockd
sudo systemctl enable uresourced

echo "Installing updates"
sudo pacman -Syyu --noconfirm || true
sudo paru --cleanafter -Syu --devel --combinedupgrade -x
sudo topgrade -c --disable config_update --skip-notify -y || true
rustup update || true
tldr -u && sudo tldr -u
echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && bootctl is-installed &>/dev/null; then
    echo "✅ systemd-boot is installed. Updating..."
    sudo bootctl update || true
    sudo bootctl cleanup || true
else
    echo "❌ systemd-boot not detected; skipping bootctl update."
fi

echo "🔍 Checking for Limine..."
if find /boot /boot/efi /mnt -type f -name "limine.cfg" 2>/dev/null | grep -q limine; then
    echo "✅ Limine configuration detected."

    # Check if `limine-update` is available
    if command -v limine-update &>/dev/null; then
        sudo limine-update || true
        sudo limine-mkinitcpio || true
    else
        echo "⚠️ limine-update not found in PATH."
    fi
else
    echo "❌ Limine configuration not found; skipping Limine actions."
fi

echo "Cleaning"
sudo pacman -Rns "$(pacman -Qtdq)" --noconfirm > /dev/null || true
flatpak uninstall --unused || true
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
