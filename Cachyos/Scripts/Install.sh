#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
sudo -v
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null || : 
SHELL="${BASH:-$(command -v bash)}"

# helpers
has(){ command -v "$1" &>/dev/null; }
# pick package helper as array for safe exec
if has paru; then pkgmgr=(paru); is_aur_helper=1
elif has yay; then pkgmgr=(yay); is_aur_helper=1
else pkgmgr=(sudo pacman); is_aur_helper=0
fi

# recommended build env
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf
export CFLAGS="${CFLAGS:--march=native -mtune=native -O3 -pipe}"
export CXXFLAGS="$CFLAGS"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export RUSTFLAGS='-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols'
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER
MPKG_FLAGS='--cleanbuild --clean --rmdeps --syncdeps --nocheck --skipinteg --skippgpcheck --skipchecksums'
GPG_FLAGS='--batch -q -z1 --compress-algo ZLIB --yes --skip-verify'
GIT_FLAGS='--depth=1 --single-branch'
# remove pacman lock if stale
[[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root /var/lib/pacman/db.lck
# sync keyring + full upgrade
"${pkgmgr[@]}" -Syq archlinux-keyring --noconfirm || :
"${pkgmgr[@]}" -Syuq --noconfirm || :

# package list (official + AUR combined)
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

# detect missing
echo "Checking installed packages..."
missing=()
for p in "${pkgs[@]}"; do
  ${pkgmgr[@]} -Qiq "$p" &>/dev/null || missing+=("$p")
done

if [[ ${#missing[@]} -eq 0 ]]; then
  printf '✔ All packages installed\n'
else
  printf '➜ Installing: %s\n' "${missing[*]}"
  # install flags: make sure you trust your packages!
  if [[ "${is_aur_helper:-0}" -eq 1 ]]; then
    aur_flags=(
      --needed --noconfirm --removemake --cleanafter --sudoloop
      --skipreview --nokeepsrc --batchinstall --combinedupgrade
      --mflags "$MPKG_FLAGS" --gitflags "$GIT_FLAGS" --gpgflags "$GPG_FLAGS"
    )
    if ! "${pkgmgr[@]}" -Sq "${aur_flags[@]}" "${missing[@]}"; then
      printf '✖ Batch install failed. Logging missing packages to %s/Desktop/failed_packages.log\n' "$HOME"
      logfile="${HOME}/Desktop/failed_packages.log"
      rm -f "$logfile"
      for p in "${missing[@]}"; do
        if ! "${pkgmgr[@]}" -Qiq "$p" &>/dev/null; then
          printf '%s\n' "$p" >>"$logfile"
        fi
      done
      printf '✖ See %s\n' "$logfile"
    else
      printf '✔ Installation complete\n'
    fi
  else
    # pacman only
    if ! "${pkgmgr[@]}" -Sq --needed --noconfirm "${missing[@]}"; then
      printf '✖ pacman install failed. Check output\n'
    else
      printf '✔ Installation complete\n'
    fi
  fi
fi

flats=(
io.github.wiiznokes.fan-control
io.github.giantpinkrobots.flatsweep
best.ellie.StartupConfiguration
)

# flatpak: install from flatpaks.lst if present
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || :
  [[ ${#flats[@]} -gt 0 ]] && flatpak install -y flathub "${flats[@]}" || :
  flatpak update -y --noninteractive
fi

# rustup + cargo utilities
if ! has rustup; then
  printf 'Installing rustup (minimal nightly)...\n'
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y -q -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

rust_crates=(
  rmz cpz xcp crabz parallel-sh parel ffzap cargo-diet crab-fetch cargo-list
  minhtml cargo-minify rimage ripunzip
)

printf 'Installing cargo crates (best-effort)...\n'
command -v sccache &>/dev/null && export RUSTC_WRAPPER=sccache
rustup default nightly || :
rustup set auto-self-update disable || :
rustup set profile minimal || :
rustup self upgrade-data || :

# install gitoxide from git (special)
cargo install -Zunstable-options -Zgit -Zavoid-dev-deps -Zno-embed-metadata -Ztrim-paths \
  --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins --profile release-github --no-default-features \
  -F http-client-reqwest,gitoxide-core-blocking-client,fast,pretty-cli,gitoxide-core-tools,prodash-render-line,prodash-render-tui,prodash/render-line-autoconfigure,gix/revparse-regex || :

# install other crates
if [ ${#rust_crates[@]} -gt 0 ]; then
  cargo install -Zunstable-options -Zgit -Zavoid-dev-deps --locked --bins --keep-going "${rust_crates[@]}" -f -q || :
fi

# micro plugins (best-effort)
if has micro; then
  mplug=(fish fzf palettero wc filemanager cheat linter lsp autofmt detectindent editorconfig misspell aspell comment diff jump bounce autoclose manipulator joinLines quoter literate status ftoptions)
  micro -plugin install "${mplug[@]}" || :
  micro -plugin update >/dev/null || :
fi

# fisher plugins for fish shell
if has fish; then
  if [ -r /usr/share/fish/vendor_functions.d/fisher.fish ]; then
    fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update" || :
    fishplug=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x scaryrawr/zoxide.fish patrickf1/fzf.fish archelaus/shell-mommy eth-p/fish-plugin-sudo rubiev/plugin-fuck paysonwallach/fish-you-should-use)
    printf '%s\n' "${fishplug[@]}" | fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; fisher install" || :
  fi
fi

# basher
#curl -sSf https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash || :

# fzf bash completions
mkdir -p "$HOME/.config/bash"
curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" -o "$HOME/.config/bash/fzf-simple-completion.sh"
chmod +x "$HOME/.config/bash/fzf-simple-completion.sh" || :

# housekeeping & system updates
has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry '(--disable={config_update,system,tldr,maza,yazi,micro})' 2>/dev/null || :
if has topgrade; then
  topno="(--disable={config_update,system,tldr,maza,yazi,micro})"
  topnosudo="(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})"
  topgrade -cy --skip-notify --no-self-update --no-retry "${topno[@]}" 2>/dev/null || :
  sudo topgrade -cy --skip-notify --no-self-update --no-retry "${topnosudo[@]}" 2>/dev/null || :
fi
has fc-cache && sudo fc-cache -f >/dev/null || :
has update-desktop-database && sudo update-desktop-database &>/dev/null || :
has fwupdmgr && { sudo fwupdmgr refresh -y && sudo fwupdtool update; }

# initramf
if has update-initramfs; then
  sudo update-initramfs || :
else
  if has limine-mkinitcpio; then
    sudo limine-mkinitcpio || :
  elif has mkinitcpio; then
    sudo mkinitcpio -P || :
  elif has /usr/lib/booster/regenerate_images; then
    sudo /usr/lib/booster/regenerate_images || :
  elif has dracut-rebuild; then
    sudo dracut-rebuild || :
  else
    printf '⚠ initramfs generator not found; update manually\n'
  fi
fi

# cleanup
orphans="$(pacman -Qdtq 2>/dev/null || :)"
[ -n "$orphans" ] && sudo pacman -Rns $orphans --noconfirm &>/dev/null || :
sudo pacman -Sccq --noconfirm &>/dev/null || :
[ "${is_aur_helper:-0}" -eq 1 ] && "${pkgmgr[@]}" -Sccq --noconfirm &>/dev/null || :
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q || :
sudo fstrim -a --quiet-unsupported || :

printf '\nAll done\n'
