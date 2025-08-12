#!/usr/bin/env bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
export LC_ALL=C LANG=C.UTF-8
sudo -v

# sudo pacman -Rns openssh 

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
lrzip
pixz
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
curl-rustls
librustls
eza
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
preload
wolfssl
openssh-hpn
openssh-hpn-shim
sshpass
graphicsmagick
fclones
)

echo -e "\nChecking installed packages..."
missing_pkgs=()
# Collect packages that are not installed
for pkg in "${packages[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    missing_pkgs+=("$pkg")
  else
    echo "✔ $pkg is already installed"
  fi
done

# Proceed with installation only if there are missing packages
if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "➜ Installing: ${missing_pkgs[*]}"
  
  while [ ${#missing_pkgs[@]} -gt 0 ]; do
      failed_pkgs=()

      # Try batch install
      sudo pacman -S --noconfirm -q "${missing_pkgs[@]}" || {
          echo "Some packages failed to install."
          # Identify failed packages
          for pkg in "${missing_pkgs[@]}"; do
              sudo pacman -S --noconfirm -q "$pkg" || failed_pkgs+=("$pkg")
          done
          # Remove failed packages from retry list
          missing_pkgs=($(echo "${missing_pkgs[@]}" | tr ' ' '\n' | grep -vxF -f <(printf "%s\n" "${failed_pkgs[@]}")))
          echo "Retrying without: ${failed_pkgs[*]}"
      }
      [ ${#failed_pkgs[@]} -eq 0 ] && break  # Stop if all succeed
  done

  echo "✔ All packages installed (or skipped if already present)."
else
  echo "✔ All packages were already installed—nothing to do."
fi

sudo pacman -S cpio bc --needed -q --noconfirm || true

aurpkgs=(
cleanerml-git
makepkg-optimize-mold
prelockd
uresourced
jdk24-graalvm-ee-bin
plzip
plzip-lzip-link
lbzip2
usb-dirty-pages-udev
cleanlib32
optipng-parallel
dxvk-gplasync-bin
pay-respects
rust-parallel
unzrip-git
adbr-git
luxtorpeda
tuckr-git
intel-ucode-shrink-hook
xdg-ninja
cylon
scaramanga
dotter-rs
kbuilder
)

while [ ${#aurpkgs[@]} -gt 0 ]; do
    failed_pkgs=()
    
    # Try installing all remaining packages
    paru -S "${aurpkgs[@]}" -q --noconfirm --removemake --cleanafter --skipreview --nokeepsrc || {
        echo "Some packages failed to install."
        
        # Identify which package failed
        for aur_pkg in "${aurpkgs[@]}"; do
            paru -S "$aur_pkg" -q --noconfirm --removemake --cleanafter --skipreview --nokeepsrc || failed_pkgs+=("$aur_pkg")
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

# Image downloads
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PinkLady.webp -o $HOME/Pictures//PinkLady.webp
curl-rustls https://github.com/Ven0m0/Linux-OS/blob/main/Cachyos/PFP.webp -o $HOME/Pictures/PFP.web

# echo "Installing gaming applications"
# sudo pacman -S cachyos-gaming-meta cachyos-gaming-applications --noconfirm || true


echo "Installing rust + components..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy,rustc-dev -t x86_64-unknown-linux-gnu,wasm32-unknown-unknown -y -q

echo "Installing Cargo crates"
cargostall(
rmz
cpz
xcp
crabz
parallel-sh
parel
ffzap
cargo-diet
crab-fetch
cargo-list
minhtml
cargo-minify
rimage
)

export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Zunstable-options -Ztune-cpu=native -Cpanic=abort -Cllvm-args=-enable-dfa-jump-thread"
cargo install --git https://github.com/GitoxideLabs/gitoxide gitoxide --no-default-features --features max-pure

# Fast, hardware-accelerated CRC calculation
cargo +nightly install crc-fast --features=optimize_crc32_auto,vpclmulqdq || true
# Faster unzip
cargo install ripunzip

# fast compression multitool for zst, tgz, txz, zip, 7z
cargo install zzz-arc
# https://github.com/caydenlund/xz-rs.git

# Rust-curl
# https://crates.io/crates/rust-curl
cargo install rust-curl

# GUI for fclones
cargo install fclones-gui

cargo install shell-mommy
paru -S mommy


# echo "enabling services"
# sudo systemctl enable pci-latency.service
# sudo systemctl enable fstrim.timer
# https://gist.github.com/dante-robinson/cd620c7283a6cc1fcdd97b2d139b72fa
# sudo systemctl enable irqbalance
# sudo systemctl enable memavaild
# sudo systemctl enable preload
# sudo systemctl enable prelockd
# sudo systemctl enable uresourced

micro -plugin install cheat editorconfig fzf filemanager autofmt quoter misspell

# Fisher fix
fisher install jorgebucaran/fisher
fisher install acomagu/fish-async-prompt

# Basher
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

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
sudo journalctl --rotate -q || true
sudo journalctl --vacuum-time=1s -q || true
sudo rm -rf /run/log/journal/*
sudo rm -rf /var/log/journal/*

echo "done"
