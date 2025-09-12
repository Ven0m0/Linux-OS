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

if command -v paru &>/dev/null; then
  aurhelper=paru
elif command -v yay &>/dev/null; then
  aurhelper=yay
else
  aurhelper="sudo pacman"
fi

# Sync keyring + upgrade
$aurhelper -Syq archlinux-keyring --noconfirm
$aurhelper -Syuq --noconfirm

# sudo pacman -Rns openssh && sudo pacman -Sq openssh-hpn openssh-hpn-shim
pkgs=(
  topgrade bauh flatpak partitionmanager polkit-kde-agent legcord prismlauncher
  obs-studio pigz lrzip pixz minizip-ng optipng svgo nasm yasm ccache sccache
  openmp polly mold autofdo-bin patchutils vulkan-mesa-layers
  plasma-wayland-protocols vkd3d-proton-git protonup-qt protonplus proton-ge-custom
  vkbasalt menu-cache profile-sync-daemon profile-cleaner bleachbit-git irqbalance
  xorg-xhost libappindicator-gtk3 libdbusmenu-glib appmenu-gtk-module
  xdg-desktop-portal modprobed-db cachyos-ksm-settings cpupower-gui openrgb
  dropbear optiimage multipath-tools preload wolfssl sshpass graphicsmagick
  fclones cpio bc fuse2 appimagelauncher jdk24-graalvm-ee-bin
  cleanerml-git makepkg-optimize-mold prelockd uresourced optipng-parallel
  plzip plzip-lzip-link lbzip2 usb-dirty-pages-udev cleanlib32 tuckr-git
  dxvk-gplasync-bin pay-respects unzrip-git adbr-git luxtorpeda
  intel-ucode-shrink-hook xdg-ninja cylon scaramanga kbuilder
)

echo "Checking installed packages..."
missing=()
for p in "${pkgs[@]}"; do
  $aurhelper -Qiq "$p" &>/dev/null || missing+=("$p")
done

if [ ${#missing[@]} -eq 0 ]; then
  echo "✔ All packages installed"
  exit 0
fi

echo "➜ Installing: ${missing[*]}"
while [ ${#missing[@]} -gt 0 ]; do
  failed=()
  $aurhelper -Sq --needed --noconfirm --removemake --cleanafter --sudoloop \
    --skipreview --nokeepsrc --batchinstall --combinedupgrade \
    --mflags '--skipinteg --skippgpcheck' "${missing[@]}" || {
      echo "Some packages failed. Retrying individually..."
      for p in "${missing[@]}"; do
        $aurhelper -Sq --needed --noconfirm --removemake --cleanafter \
          --skipreview --nokeepsrc "$p" || failed+=("$p")
      done
      missing=($(printf "%s\n" "${missing[@]}" | grep -vxF -f <(printf "%s\n" "${failed[@]}")))
  }
  [ ${#failed[@]} -eq 0 ] && break
done

echo "✔ Installation complete (or skipped if already present)"

if command -v flatpak &>/dev/null; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flats=`awk -F '#' '{print $1}' "${WORKDIR:-$PWD}"/flatpaks.lst | sed 's/ //g' | xargs`
  flatpak install -y flathub ${flats}
  flatpak install -y flathub org.kde.audiotube
fi
# echo "Installing gaming applications"
# sudo pacman -Sq cachyos-gaming-meta cachyos-gaming-applications --noconfirm --needed || :

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
ripunzip
)

RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
rustup default nightly
rustup set auto-self-update disable
rustup set profile minimal
rustup self upgrade-data

command -v sccache &>/dev/null && export RUSTC_WRAPPER=sccache

cargo install -Zunstable-options -Zgit -Zavoid-dev-deps -Zno-embed-metadata -Ztrim-paths --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins --profile release-github --no-default-features -F http-client-reqwest,gitoxide-core-blocking-client,fast,pretty-cli,gitoxide-core-tools,prodash-render-line,prodash-render-tui,prodash/render-line-autoconfigure,gix/revparse-regex

cargo install -Zunstable-options -Zgit -Zgitoxide -Zavoid-dev-deps -Zno-embed-metadata -Ztrim-paths "${cargostall[@]}" -f -q --locked --bins --keep-going

#cargo install shell-mommy
#paru -S mommy

# echo "enabling services"
# sudo systemctl enable pci-latency.service
# sudo systemctl enable fstrim.timer
# https://gist.github.com/dante-robinson/cd620c7283a6cc1fcdd97b2d139b72fa
# sudo systemctl enable irqbalance
# sudo systemctl enable memavaild
# sudo systemctl enable preload
# sudo systemctl enable prelockd
# sudo systemctl enable uresourced

# https://github.com/hidaruma/micro-textlint-plugin
mplug=(
fish fzf palettero wc
filemanager cheat
linter lsp autofmt detectindent editorconfig
misspell aspell comment diff
jump bounce autoclose
manipulator joinLines quoter
literate status ftoptions
)
micro -plugin install "${mplug[@]}"

# Fisher fix
#fisher install jorgebucaran/fisher
#fisher install acomagu/fish-async-prompt
fishplug=(
acomagu/fish-async-prompt
kyohsuke/fish-evalcache
eugene-babichenko/fish-codegen-cache
oh-my-fish/plugin-xdg
wk/plugin-ssh-term-helper
scaryrawr/cheat.sh.fish
y3owk1n/fish-x
scaryrawr/zoxide.fish
patrickf1/fzf.fish
archelaus/shell-mommy
eth-p/fish-plugin-sudo
rubiev/plugin-fuck
)
if has fish; then
  if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
    fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update"
    printf '%s\n' "${fishplug[@]}" | fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; fisher install"
   fi
fi

# Basher
curl -sSf https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

echo "Install fzf bash tap completions"
mkdir -p "${HOME}/.config/bash"
curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" -o "${HOME}/.config/bash/fzf-simple-completion.sh"
chmod +x "${HOME}/.config/bash/fzf-simple-completion.sh"

echo "Installing updates"
has tldr && sudo tldr -cuq
if has topgrade; then
  echo 'update using topgrade...'
  topno="(--disable={config_update,system,tldr,maza,yazi,micro})"
  topnosudo="(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})"
  LC_ALL=C topgrade -cy --skip-notify --no-self-update --no-retry "${topno[@]}" 2>/dev/null || :
  LC_ALL=C sudo topgrade -cy --skip-notify --no-self-update --no-retry "${topnosudo[@]}" 2>/dev/null || :
fi
has fc-cache && sudo fc-cache -f >/dev/null
has update-desktop-database && sudo update-desktop-database &>/dev/null
if has fwupdmgr; then
  sudo fwupdmgr refresh -y
  sudo fwupdtool update
fi
if has bootctl; then
  sudo bootctl update -q &>/dev/null; sudo bootctl cleanup -q &>/dev/null
fi
if has sdboot-manage; then
  echo 'update sdboot-manage...'
  sudo sdboot-manage remove 2>/dev/null
  sudo sdboot-manage update &>/dev/null
fi
if has update-initramfs; then
  sudo update-initramfs
else
  if has limine-mkinitcpio; then
    sudo limine-mkinitcpio
  elif has mkinitcpio; then
    sudo mkinitcpio -P
  elif has "/usr/lib/booster/regenerate_images"; then
    sudo /usr/lib/booster/regenerate_images
  elif has dracut-rebuild; then
    sudo dracut-rebuild
  else
    echo -e "\e[31m The initramfs generator was not found, please update initramfs manually\e[0m"
  fi
fi

echo "Cleaning"
sudo pacman -Rns "$(pacman -Qdtq 2>/dev/null)" --noconfirm >/dev/null
sudo pacman -Sccq --noconfirm
sudo $aurhelper -Sccq --noconfirm
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q
sudo fstrim -a --quiet-unsupported

echo -e "\nAll done ✅ (> ^ <) Meow\n"
