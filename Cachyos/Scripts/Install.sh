#!/usr/bin/env bash
export LC_ALL='C' LANG='C'
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#============ Helpers ====================
has(){ local x="${1:?no argument}"; x=$(command -v -- "$x") &>/dev/null || return 1; [[ -x $x ]] || return 1; }
hasname(){ local x="${1:?no argument}"; x=$(type -P -- "$x" 2>/dev/null) || return 1; printf '%s\n' "${x##*/}"; }
#============ Safe optimal privilege tool ====================
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)" || { printf '%s\n' "❌ No valid privilege escalation tool found." >&2; exit 1; }
[[ -z ${suexec:-} ]] && { printf '%s\n' "❌ No valid privilege escalation tool found." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v
export HOME="/home/${SUDO_USER:-$USER}"
#============ Env ====================
[[ -r /etc/makepkg.conf ]] && . "/etc/makepkg.conf"
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
CFLAGS="${CFLAGS:=-march=native -mtune=native -O3 -pipe}" 
CXXFLAGS="$CFLAGS"
MAKEFLAGS="-j$(nproc)"
CARGO_CACHE_RUSTC_INFO=1 CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always RUSTUP_TOOLCHAIN=nightly #RUSTC_BOOTSTRAP=1
export MAKEFLAGS RUSTFLAGS CFLAGS CXXFLAGS CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
#=============================================================
[[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root -- '/var/lib/pacman/db.lck'
sync
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
libdbusmenu-glib
appmenu-gtk-module
xdg-desktop-portal 
modprobed-db
cachyos-ksm-settings
cpupower-gui
openrgb
dropbear
optiimage
multipath-tools
preload
wolfssl
openssh-hpn
openssh-hpn-shim
sshpass
graphicsmagick
fclones
cpio
bc
flatpak
fuse2
appimagelauncher
)

echo -e "\nChecking installed packages..."
missing_pkgs=()
# Collect packages that are not installed
for pkg in "${packages[@]}"; do
  if ! pacman -Qiq "$pkg" &>/dev/null; then
    missing_pkgs+=("$pkg")
  else
    echo "✔ ${pkg} is already installed"
  fi
done
# Proceed with installation only if there are missing packages
if [ ${#missing_pkgs[@]} -gt 0 ]; then
  echo "➜ Installing: ${missing_pkgs[*]}"
  while [ ${#missing_pkgs[@]} -gt 0 ]; do
      failed_pkgs=()
      # Try batch install
      sudo pacman -Sq --needed --noconfirm "${missing_pkgs[@]}" || {
          echo "Some packages failed to install."
          # Identify failed packages
          for pkg in "${missing_pkgs[@]}"; do
              sudo pacman -Sq --needed --noconfirm "$pkg" || failed_pkgs+=("$pkg")
          done
          # Remove failed packages from retry list
          missing_pkgs=($(echo "${missing_pkgs[@]}" | tr ' ' '\n' | grep -vxF -f <(printf "%s\n" "${failed_pkgs[@]}")))
          echo "Retrying without: ${failed_pkgs[*]}"
      }
      [ ${#failed_pkgs[@]} -eq 0 ] && break  # Stop if all succeed
  done
  echo "✔ All packages installed (or skipped if present)."
else
  echo "✔ All packages were already installed—nothing to do."
fi

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
unzrip-git
adbr-git
luxtorpeda
tuckr-git
intel-ucode-shrink-hook
xdg-ninja
cylon
scaramanga
kbuilder
)

while [ ${#aurpkgs[@]} -gt 0 ]; do
    failed_pkgs=() # Try installing all remaining packages
    paru -Sq "${aurpkgs[@]}" --needed --noconfirm --removemake --cleanafter --skipreview --nokeepsrc || { echo "Some packages failed to install." \
        # Identify which package failed
        for aur_pkg in "${aurpkgs[@]}"; do paru -Sq "$aur_pkg" --needed --noconfirm --removemake --cleanafter --skipreview --nokeepsrc || failed_pkgs+=("$aur_pkg"); done; \
        # Remove failed packages from the list
        aurpkgs=($(echo "${aurpkgs[@]}" | tr ' ' '\n' | grep -vxF -f <(printf "%s\n" "${failed_pkgs[@]}"))); echo "Retrying without: ${failed_pkgs[*]}"; }
    [ ${#failed_pkgs[@]} -eq 0 ] && { echo "AUR package installation complete."; break; }
done

# konsave
# memavaild
# precached
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

flats=`awk -F '#' '{print $1}' "${WORKDIR:-$PWD}"/flatpaks.lst | sed 's/ //g' | xargs`
flatpak install -y flathub ${flats}
flatpak install -y flathub org.kde.audiotube

# echo "Installing gaming applications"
# sudo pacman -S cachyos-gaming-meta cachyos-gaming-applications --noconfirm || true


foxdir(){
  local PROFILE_DIR="${HOME}/.mozilla/firefox" ACTIVE_PROF ACTIVE_PROF_DIR
  ACTIVE_PROF=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1; next} f && /^Default=/{print $2; exit}' "${PROFILE_DIR}/installs.ini" 2>/dev/null)
  [[ -z "$ACTIVE_PROF" ]] && { ACTIVE_PROF=$(awk -F= '/^\[.*\]/{f=0} /^\[Profile[0-9]+\]/{f=1} f && /^Default=1/ {found=1} f && /^Path=/{if(found){print $2; exit}}' "${PROFILE_DIR}/profiles.ini" 2>/dev/null); }
  [[ -n "$ACTIVE_PROF" ]] && { ACTIVE_PROF_DIR="${PROFILE_DIR}/${ACTIVE_PROF}"; export ACTIVE_PROF_DIR; } || { echo "❌ Could not determine active Firefox profile." >&2; exit 1; }
}
FOXYDIR="$(foxdir)"

# Rust packages
rustchain='
rust-bindgen
cbindgen
cargo-c
cargo-cache
cargo-machete
cargo-pgo
cargo-update
cargo-llvm-cov
# aurs
dotter-rs
rust-parallel
uutils-coreutils
sudo-rs
curl-rustls
librustls
eza
dust
sd
'

url="https://raw.githubusercontent.com/CodesOfRishi/navita/main/navita.sh"
dest="${HOME}/.config/bash"
mkdir -p "$dest"
curl -sSfL --create-dirs -o "$dest/$(basename "$url")" "$url" 
chmod +x "${dest}/$(basename "${url}")" && . "${dest}/$(basename "${url}")"

if ! command -v rustup; then
  echo "Installing rust + components..."
  RUSTUP_QUIET=yes
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y -q -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy
fi

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

RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
rustup default nightly
rustup set auto-self-update
rustup set profile minimal
rustup self upgrade-data

cargo +nightly install --git https://github.com/GitoxideLabs/gitoxide gitoxide --no-default-features --features max-pure

# Fast, hardware-accelerated CRC calculation
cargo +nightly install crc-fast --features=optimize_crc32_auto,vpclmulqdq
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
#fisher install jorgebucaran/fisher
#fisher install acomagu/fish-async-prompt

# Basher
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

echo "Install fzf bash tap completions"
mkdir -p "$HOME/.config/bash"
curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" -o "${HOME}/.config/bash/fzf-simple-completion.sh"
chmod +x "${HOME}/.config/bash/fzf-simple-completion.sh"
[[ -f $HOME/.config/bash/fzf-simple-completion.sh ]] && . "${HOME}/.config/bash/fzf-simple-completion.sh"


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
