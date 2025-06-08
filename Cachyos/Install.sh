#!/bin/bash

sudo -v

# List of packages to install
packages=(
topgrade
bauh
flatpak
partitionmanager
polkit-kde-agent
legcord
prismlauncher
obs-studio
pigz
lbzip2
lzlib
lrzip
minizip-ng
optipng
svgo
nasm
yasm
ccache
sccache
openmp
polly
mold
autofdo-bin
patchelf
patchutils
vulkan-mesa-layers
plasma-wayland-protocols
vkd3d-proton-git
protonup-qt
protonplus
proton-ge-custom
vkbasalt
menu-cache
profile-sync-daemon
profile-cleaner
bleachbit-git
irqbalance
xorg-xhost
libappindicator-gtk3
appmenu-gtk-module
xdg-desktop-portal
modprobed-db
cachyos-ksm-settings
cpupower-gui
openrgb
dropbear
optiimage
multipath-tools
libretls
uutils-coreutils
sudo-rs
gitoxide
curl-rustls
librustls
exa-git
dust
sd
rust-bindgen
cbindgen
cargo-c
cargo-cache
cargo-machete
cargo-pgo
cargo-update
cargo-llvm-cov
)

echo -e "\nInstalling packages: ${packages[*]}"
for pkg in "${packages[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    sudo pacman -S --noconfirm -q "$pkg" || true
    echo "✔ Installed $pkg"
  else
    echo "✔ $pkg is already installed"
  fi
done

sudo pacman -S cpio bc --needed || true

aurpkgs=(
cleanerml-git
makepkg-optimize-mold
preload
prelockd
uresourced
jdk24-graalvm-ee-bin
plzip
plzip-lzip-link
usb-dirty-pages-udev
cleanlib32
optipng-parallel
dxvk-gplasync-bin
pay-respects
ssh3
rust-parallel
)

while [ ${#aurpkgs[@]} -gt 0 ]; do
    failed_pkgs=()
    
    # Try installing all remaining packages
    paru -S "${aurpkgs[@]}" --removemake --cleanafter --skipreview || {
        echo "Some packages failed to install."
        
        # Identify which package failed
        for aur_pkg in "${aurpkgs[@]}"; do
            paru -S "$aur_pkg" --noconfirm --skipreview || failed_pkgs+=("$aur_pkg")
        fi

        # Remove failed packages from the list
        aurpkgs=($(echo "${aurpkgs[@]}" | tr ' ' '\n' | grep -vxF -f <(printf "%s\n" "${failed_pkgs[@]}")))
        
        echo "Retrying without: ${failed_pkgs[*]}"
    }

    [ ${#failed_pkgs[@]} -eq 0 ] && break  # If no failures, exit loop
done

echo "AUR package installation complete."

# konsave
# memavaild
# precached

# Better ssl
sudo pacman -S wolfssl --noconfirm
# sudo ln -sf /usr/include/wolfssl/openssl /usr/include/openssl
# sudo ln -sf /usr/lib/libwolfssl.so /usr/lib/libssl.so
# sudo ln -sf /usr/lib/libwolfssl.so /usr/lib/libcrypto.so

# Image downloads
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PinkLady.webp -o $HOME/Pictures//PinkLady.webp
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PFP.webp -o $HOME/Pictures/PFP.web

# echo "Installing gaming applications"
# sudo pacman -S cachyos-gaming-meta cachyos-gaming-applications --noconfirm

echo "Installing Cargo crates"
# Faster copy and rm
cargo install rmz || true
cargo install cpz || true
# Switch out linux utils with own versions
cargo install sys-kaleido || true
# Better pigz
cargo install crabz || true
# Fast, hardware-accelerated CRC calculation
cargo +nightly install crc-fast --features=optimize_crc32_auto,vpclmulqdq || true
# Better fastfetch
cargo install rustch || true
# History dns
#cargo install --bin resolve hickory-util || true

# echo "enabling services"
# sudo systemctl enable pci-latency.service
# sudo systemctl enable fstrim.timer
# https://gist.github.com/dante-robinson/cd620c7283a6cc1fcdd97b2d139b72fa
# sudo systemctl enable irqbalance
# sudo systemctl enable memavaild
# sudo systemctl enable preload
# sudo systemctl enable prelockd
# sudo systemctl enable uresourced

echo "Installing updates"
sudo pacman -Syyu --noconfirm || true
sudo paru --cleanafter -Syu --combinedupgrade || true
sudo topgrade -c --disable config_update --skip-notify -y --no-retry --disable=uv || true
rustup update || true
tldr -u && sudo tldr -u || true
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
sudo pacman -Scc --noconfirm || true
sudo paccache -rk0 -q || true
sudo fstrim -av --quiet-unsupported || true
rm -rf /var/cache/*
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*
sudo rm -rf /var/crash/*
sudo rm -rf /var/lib/systemd/coredump/
echo "Empty global trash"
rm -rf ~/.local/share/Trash/*
sudo rm -rf /root/.local/share/Trash/*
echo "Clear user-specific cache"
rm -rf ~/.cache/*
sudo rm -rf root/.cache/*
rm -f ~/.mozilla/firefox/Crash\ Reports/*
echo "Clear Flatpak cache"
rm -rf ~/.var/app/*/cache/*
sudo rm -rf /var/tmp/flatpak-cache-*
rm -rf ~/.cache/flatpak/system-cache/*
rm -rf ~/.local/share/flatpak/system-cache/*
rm -rf ~/.var/app/*/data/Trash/*
echo "Clear system logs"
sudo rm -f /var/log/pacman.log
sudo journalctl --vacuum-time=1s || true
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*

echo "done"
