#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
sudo -v
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null || :

SHELL="${BASH:-$(command -v bash)}"
has(){ command -v "$1" &>/dev/null; }

# Package manager detection
if has paru; then pkgmgr=(paru); is_aur=1
elif has yay; then pkgmgr=(yay); is_aur=1
else pkgmgr=(sudo pacman); is_aur=0; fi

# Build environment
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf
export CFLAGS="${CFLAGS:--march=native -mtune=native -O3 -pipe}"
export CXXFLAGS="$CFLAGS" AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export RUSTFLAGS='-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols'
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER

MPKG_FLAGS='--cleanbuild --clean --rmdeps --syncdeps --nocheck --skipinteg --skippgpcheck --skipchecksums'
GPG_FLAGS='--batch -q -z1 --compress-algo ZLIB --yes --skip-verify'
GIT_FLAGS='--depth=1 --single-branch'

# Remove stale lock
[[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root /var/lib/pacman/db.lck

# Sync keyring + system update
"${pkgmgr[@]}" -Syq archlinux-keyring --noconfirm || :
"${pkgmgr[@]}" -Syuq --noconfirm || :

# Packages (official + AUR)
pkgs=(topgrade bauh flatpak partitionmanager polkit-kde-agent legcord prismlauncher
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
      intel-ucode-shrink-hook xdg-ninja cylon scaramanga kbuilder)

# Detect missing
echo "Checking installed packages..."
missing=()
for p in "${pkgs[@]}"; do ${pkgmgr[@]} -Qiq "$p" &>/dev/null || missing+=("$p"); done

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '➜ Installing: %s\n' "${missing[*]}"
  if [[ "$is_aur" -eq 1 ]]; then
    aur_flags=(--needed --noconfirm --removemake --cleanafter --sudoloop
               --skipreview --nokeepsrc --batchinstall --combinedupgrade
               --mflags "$MPKG_FLAGS" --gitflags "$GIT_FLAGS" --gpgflags "$GPG_FLAGS")
    if ! "${pkgmgr[@]}" -Sq "${aur_flags[@]}" "${missing[@]}"; then
      logfile="${HOME}/Desktop/failed_packages.log"
      printf '✖ Batch install failed. Logging missing packages to %s\n' "$logfile"
      rm -f "$logfile"
      for p in "${missing[@]}"; do
        ${pkgmgr[@]} -Qiq "$p" &>/dev/null || printf '%s\n' "$p" >>"$logfile"
      done
    fi
  else
    "${pkgmgr[@]}" -Sq --needed --noconfirm "${missing[@]}" || printf '✖ pacman install failed\n'
  fi
else
  printf '✔ All packages installed\n'
fi

# Flatpak
flats=(
io.github.wiiznokes.fan-control
io.github.giantpinkrobots.flatsweep
best.ellie.StartupConfiguration
)
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || :
  [[ ${#flats[@]} -gt 0 ]] && flatpak install -y flathub "${flats[@]}" || :
  flatpak update -y --noninteractive
fi

# Rust + Cargo
if ! has rustup; then
  curl -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y -q -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

rust_crates=(rmz cpz xcp crabz parallel-sh parel ffzap cargo-diet crab-fetch cargo-list minhtml cargo-minify rimage ripunzip)

command -v sccache &>/dev/null && export RUSTC_WRAPPER=sccache
rustup default nightly || :; rustup set auto-self-update disable || :; rustup set profile minimal || :; rustup self upgrade-data || :

cargo install -Zunstable-options -Zgit -Zavoid-dev-deps -Zno-embed-metadata -Ztrim-paths \
  --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins --profile release-github --no-default-features \
  -F http-client-reqwest,gitoxide-core-blocking-client,fast,pretty-cli,gitoxide-core-tools,prodash-render-line,prodash-render-tui,prodash/render-line-autoconfigure,gix/revparse-regex || :

[ ${#rust_crates[@]} -gt 0 ] && cargo install -Zunstable-options -Zgit -Zavoid-dev-deps --locked --bins --keep-going "${rust_crates[@]}" -f -q || :

# Micro plugins
has micro && micro -plugin install fish fzf palettero wc filemanager cheat linter lsp autofmt detectindent editorconfig misspell aspell comment diff jump bounce autoclose manipulator joinLines quoter literate status ftoptions || : && micro -plugin update >/dev/null || :

# Fish plugins
if has fish && [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
  fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; and fisher update" || :
  fishplug=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x scaryrawr/zoxide.fish patrickf1/fzf.fish archelaus/shell-mommy eth-p/fish-plugin-sudo rubiev/plugin-fuck paysonwallach/fish-you-should-use)
  printf '%s\n' "${fishplug[@]}" | fish -c ". /usr/share/fish/vendor_functions.d/fisher.fish; fisher install" || :
fi

# Bash completions
mkdir -p "$HOME/.config/bash"
curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/main/fzf-simple-completion.sh" -o "$HOME/.config/bash/fzf-simple-completion.sh"
chmod +x "$HOME/.config/bash/fzf-simple-completion.sh" || :

# Housekeeping
has topgrade && { topgrade -cy --skip-notify --no-self-update --no-retry '(--disable={config_update,system,tldr,maza,yazi,micro})' 2>/dev/null || :; sudo topgrade -cy --skip-notify --no-self-update --no-retry '(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})' 2>/dev/null || :; }
has fc-cache && sudo fc-cache -f >/dev/null || :
has update-desktop-database && sudo update-desktop-database &>/dev/null || :
has fwupdmgr && { sudo fwupdmgr refresh -y && sudo fwupdtool update; }

# Initramfs
if has update-initramfs; then sudo update-initramfs || :
elif has limine-mkinitcpio; then sudo limine-mkinitcpio || :
elif has mkinitcpio; then sudo mkinitcpio -P || :
elif has /usr/lib/booster/regenerate_images; then sudo /usr/lib/booster/regenerate_images || :
elif has dracut-rebuild; then sudo dracut-rebuild || :
else printf '⚠ initramfs generator not found; update manually\n'; fi

# Cleanup
orphans=$(pacman -Qdtq 2>/dev/null || :)
[ -n "$orphans" ] && sudo pacman -Rns $orphans --noconfirm &>/dev/null || :
sudo pacman -Sccq --noconfirm &>/dev/null || :
[ "$is_aur" -eq 1 ] && "${pkgmgr[@]}" -Sccq --noconfirm &>/dev/null || :
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q || :
sudo fstrim -a --quiet-unsupported || :

printf '\nAll done\n'
