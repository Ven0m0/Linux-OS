#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
sudo -v

export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null || :
SHELL=bash jobs=$(nproc)

has() { command -v "$1" >/dev/null 2>&1; }
msg() { printf '\e[1;33m► %s\e[0m\n' "$*"; }
die() { printf '\e[1;31m✖ %s\e[0m\n' "$*" >&2; exit "${2:-1}"; }
log() { printf '\e[1;36m✓ %s\e[0m\n' "$*"; }

# Package manager detection
if has paru; then pkgmgr=(paru) aur=1
elif has yay; then pkgmgr=(yay) aur=1
else pkgmgr=(sudo pacman) aur=0
fi

# Build environment (consolidated exports)
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib \
  MAKEFLAGS="-j$jobs" NINJAFLAGS="-j$jobs" GOMAXPROCS="$jobs" CARGO_BUILD_JOBS="$jobs" \
  CFLAGS="${CFLAGS:--O3 -march=native -mtune=native -pipe}" \
  CXXFLAGS="${CXXFLAGS:-$CFLAGS}" \
  RUSTFLAGS="${RUSTFLAGS:--Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clinker-plugin-lto -Cllvm-args=-enable-dfa-jump-thread -Clinker=clang -Clinker-features=+lld -Zunstable-options -Ztune-cpu=native -Zfunction-sections -Zfmt-debug=none -Zlocation-detail=none}" \
  CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true OPT_LEVEL=3 CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1 \
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_OPT_LEVEL=3 \
  UV_COMPILE_BYTECODE=1 UV_NO_VERIFY_HASHES=1 UV_SYSTEM_PYTHON=1 UV_FORK_STRATEGY=fewest UV_RESOLUTION=highest \
  ZSTD_NBTHREADS=0 FLATPAK_FORCE_TEXT_AUTH=1 PYTHONOPTIMIZE=2 PYTHON_JIT=1
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER PYTHONDONTWRITEBYTECODE

# Remove stale lock + sync keyring
sudo rm -f /var/lib/pacman/db.lck 2>/dev/null || :
"${pkgmgr[@]}" -Syq archlinux-keyring --noconfirm 2>/dev/null || :
"${pkgmgr[@]}" -Syyuq --noconfirm 2>/dev/null || :

# Package list
pkgs=(
  topgrade bauh flatpak partitionmanager polkit-kde-agent prismlauncher
  obs-studio pigz lrzip pixz minizip-ng optipng svgo nasm yasm ccache sccache
  openmp polly mold autofdo-bin patchutils vulkan-mesa-layers
  plasma-wayland-protocols vkd3d-proton-git protonup-qt protonplus proton-ge-custom
  vkbasalt menu-cache profile-sync-daemon profile-cleaner bleachbit-git irqbalance
  xorg-xhost libappindicator-gtk3 libdbusmenu-glib appmenu-gtk-module
  xdg-desktop-portal modprobed-db cachyos-ksm-settings cpupower-gui openrgb
  optiimage multipath-tools preload sshpass graphicsmagick
  fclones cpio bc fuse2 appimagelauncher jdk24-graalvm-ee-bin
  cleanerml-git makepkg-optimize-mold prelockd uresourced optipng-parallel
  plzip plzip-lzip-link lbzip2 usb-dirty-pages-udev cleanlib32
  dxvk-gplasync-bin pay-respects unzrip-git adbr-git luxtorpeda-git av1an
  xdg-ninja cylon scaramanga kbuilder yadm starship shfmt shellcheck shellharden dash
)

# Efficient missing package detection
mapfile -t installed < <(pacman -Qq)
declare -A inst; for p in "${installed[@]}"; do inst[$p]=1; done
missing=(); for p in "${pkgs[@]}"; do [[ ${inst[$p]} ]] || missing+=("$p"); done

# Install missing packages
if (( ${#missing[@]} )); then
  msg "Installing ${#missing[@]} packages: ${missing[*]:0:50}..."
  if (( aur )); then
    "${pkgmgr[@]}" -Sq --needed --noconfirm --removemake --cleanafter --sudoloop \
      --skipreview --nokeepsrc --batchinstall --combinedupgrade \
      --mflags '--cleanbuild --clean --rmdeps --syncdeps --nocheck --skipinteg --skippgpcheck --skipchecksums' \
      --gitflags '--depth=1' --gpgflags '--batch -q -z1 --yes --skip-verify' \
      "${missing[@]}" 2>/dev/null || {
      printf '%s\n' "${missing[@]}" > "${HOME}/Desktop/failed_packages.log"
      die "Install failed. See ~/Desktop/failed_packages.log"
    }
  else
    "${pkgmgr[@]}" -Sq --needed --noconfirm "${missing[@]}" 2>/dev/null || die "Install failed"
  fi
  log "Installed ${#missing[@]} packages"
else
  log "All packages installed"
fi

# Flatpak (consolidated)
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || :
  flatpak install -y flathub io.github.wiiznokes.fan-control 2>/dev/null || :
  flatpak update -y --noninteractive 2>/dev/null || :
fi

# Rust toolchain (streamlined)
if ! has rustup; then
  msg "Installing rustup..."
  tmp=$(mktemp) || die "mktemp failed"
  trap "rm -f $tmp" EXIT
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > "$tmp"
  sh "$tmp" --profile minimal --default-toolchain nightly -y -q \
    -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy 2>/dev/null
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

# Cargo utilities
rust_crates=(
  rmz cpz xcp crabz parallel-sh parel ffzap cargo-diet crab-fetch cargo-list 
  minhtml cargo-minify rimage ripunzip terminal_tools imagineer docker-image-pusher 
  image-optimizer dui-cli imgc pixelsqueeze bgone dupimg simagef compresscli 
  dssim img-squeeze lq
)

has sccache && export RUSTC_WRAPPER=sccache
rustup default nightly 2>/dev/null || :
rustup set auto-self-update disable 2>/dev/null || :
rustup set profile minimal 2>/dev/null || :
rustup self upgrade-data 2>/dev/null || :

# Install gitoxide (optimized)
cargo +nightly -Zgit -Zno-embed-metadata -Zbuild-std=std,panic_abort \
  -Zbuild-std-features=panic_immediate_abort install \
  --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins \
  --no-default-features --locked --features max-pure 2>/dev/null || :

# Parallel cargo installs
msg "Installing ${#rust_crates[@]} Rust crates..."
printf '%s\n' "${rust_crates[@]}" | xargs -P"$jobs" -I{} sh -c \
  'cargo +nightly install -Zunstable-options -Zgit -Zgitoxide -Zavoid-dev-deps -Zno-embed-metadata --locked {} -f -q 2>/dev/null' || :

# Micro plugins
if has micro; then
  micro -plugin install fish fzf wc filemanager cheat linter lsp autofmt detectindent editorconfig \
    misspell comment diff jump bounce autoclose manipulator joinLines literate status ftoptions 2>/dev/null || :
  micro -plugin update 2>/dev/null || :
fi

# GitHub CLI + extensions
if ! has gh; then
  sudo pacman -Sq github-cli --noconfirm --needed 2>/dev/null || :
fi
has gh && {
  gh extension install gennaro-tedesco/gh-f 2>/dev/null || :
  gh extension install gennaro-tedesco/gh-s 2>/dev/null || :
}

# Go + cod
if ! has go; then
  sudo pacman -Sq go --noconfirm --needed 2>/dev/null || :
fi
has go && go install github.com/dim-an/cod@latest 2>/dev/null || :

# Mise version manager
has mise || curl -fsSL https://mise.jdx.dev/install.sh | sh 2>/dev/null || :

# GraalVM via sdkman
has sdk && sdk install java 25-graal 2>/dev/null || :

# Soar package manager
curl -fsSL https://raw.githubusercontent.com/pkgforge/soar/main/install.sh | sh 2>/dev/null || :

# System updates
has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry \
  '(-disable={config_update,system,tldr,maza,yazi,micro})' 2>/dev/null || :
has fc-cache && sudo fc-cache -f 2>/dev/null || :
has update-desktop-database && sudo update-desktop-database 2>/dev/null || :
has fwupdmgr && sudo fwupdmgr refresh -y 2>/dev/null && sudo fwupdtool update 2>/dev/null || :

# Initramfs update
for cmd in update-initramfs limine-mkinitcpio mkinitcpio /usr/lib/booster/regenerate_images dracut-rebuild; do
  if has "$cmd" || [[ -x $cmd ]]; then
    sudo "$cmd" ${cmd##*/mkinitcpio} 2>/dev/null && break
  fi
done

# Cleanup (consolidated)
orphans=$(pacman -Qdtq 2>/dev/null) && [[ -n $orphans ]] && sudo pacman -Rns $orphans --noconfirm 2>/dev/null || :
sudo pacman -Sccq --noconfirm 2>/dev/null || :
(( aur )) && "${pkgmgr[@]}" -Sccq --noconfirm 2>/dev/null || :
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
sudo fstrim -a --quiet-unsupported 2>/dev/null || :

# Shell setup (optimized functions)
msg "Setting up shell integration..."

if has fish; then
  mkdir -p "$HOME/.config/fish/conf.d"
  fish -c "fish_update_completions" 2>/dev/null || :
  if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
    fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher update" 2>/dev/null || :
    fishplug=(
      acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache
      oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x
      scaryrawr/zoxide kpbaks/autols.fish patrickf1/fzf.fish jorgebucaran/autopair.fish
      wawa19933/fish-systemd halostatue/fish-rust kpbaks/zellij.fish
    )
    printf '%s\n' "${fishplug[@]}" | fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher install" 2>/dev/null || :
  fi
fi

if has bash; then
  mkdir -p "$HOME/.config/bash"
  curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" \
    -o "$HOME/.config/bash/fzf-simple-completion.sh" && chmod +x "$_" 2>/dev/null || :
fi

if has zsh; then
  [[ ! -f "$HOME/.p10k.zsh" ]] && curl -fsSL \
    "https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-lean.zsh" \
    -o "$HOME/.p10k.zsh" 2>/dev/null || :
  [[ ! -f "$HOME/.zshenv" ]] && echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
  mkdir -p "$HOME/.config/zsh" "$HOME/.local/share/zinit"
  [[ ! -d "$HOME/.local/share/zinit/zinit.git" ]] && \
    git clone --depth=1 https://github.com/zdharma-continuum/zinit.git \
    "$HOME/.local/share/zinit/zinit.git" 2>/dev/null || :
fi

log "Installation complete! Restart your shell."
