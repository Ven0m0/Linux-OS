#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null||:
SHELL=bash
jobs="$(nproc)"
# Helper functions
has(){ command -v "$1" &>/dev/null; }
HotMsg(){ echo -e "\e[1;33m► $1\e[0m"; }
die(){ echo -e "\e[1;31m✖ $1\e[0m" >&2; exit "${2:-1}"; }
log(){ echo -e "\e[1;36m✓ $1\e[0m"; }

# Pick package helper
if has paru; then
  pkgmgr=(paru); is_aur_helper=1
elif has yay; then
  pkgmgr=(yay); is_aur_helper=1
else
  pkgmgr=(sudo pacman); is_aur_helper=0
fi

# Build environment setup
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf
: "${CFLAGS:=-O3 -march=native -mtune=native -pipe}}"
: "${CXXFLAGS:=$CFLAGS}"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib 
export MAKEFLAGS="-j$jobs" NINJAFLAGS="-j$jobs" GOMAXPROCS="$jobs" CARGO_BUILD_JOBS="$jobs"
: "${RUSTFLAGS:=-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clinker-plugin-lto -Cllvm-args=-enable-dfa-jump-thread \
-Clinker=clang -Clinker-features=+lld -Zunstable-options -Ztune-cpu=native -Zfunction-sections -Zfmt-debug=none -Zlocation-detail=none}"
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true OPT_LEVEL=3 CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_OPT_LEVEL=3
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER PYTHONDONTWRITEBYTECODE
export UV_COMPILE_BYTECODE=1 UV_NO_VERIFY_HASHES=1 UV_SYSTEM_PYTHON=1 UV_FORK_STRATEGY=fewest UV_RESOLUTION=highest
export ZSTD_NBTHREADS=0 FLATPAK_FORCE_TEXT_AUTH=1 PYTHONOPTIMIZE=2 PYTHON_JIT=1
MPKG_FLAGS='--cleanbuild --clean --rmdeps --syncdeps --nocheck --skipinteg --skippgpcheck --skipchecksums'
GPG_FLAGS='--batch -q -z1 --yes --skip-verify'
GIT_FLAGS='--depth=1'
sudo -v

# Remove pacman lock if stale
[[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root /var/lib/pacman/db.lck
# Sync keyring + full upgrade
"${pkgmgr[@]}" -Syq archlinux-keyring --noconfirm||:
"${pkgmgr[@]}" -Syyuq --noconfirm||:

# Package list (official + AUR combined)
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

# Detect missing packages - using hash map for O(1) lookups
mapfile -t installed < <(pacman -Qq)
declare -A inst_map; for p in "${installed[@]}"; do inst_map[$p]=1; done
missing=(); for p in "${pkgs[@]}"; do [[ ${inst_map[$p]} ]]||missing+=("$p"); done

# Install missing packages
if [[ ${#missing[@]} -eq 0 ]]; then
  log "All packages installed"
else
  HotMsg "Installing: ${missing[*]}"
  if [[ "${is_aur_helper:-0}" -eq 1 ]]; then
    aur_flags=(
      --needed --noconfirm --removemake --cleanafter --sudoloop
      --skipreview --nokeepsrc --batchinstall --combinedupgrade
      --mflags "$MPKG_FLAGS" --gitflags "$GIT_FLAGS" --gpgflags "$GPG_FLAGS"
    )
    if ! "${pkgmgr[@]}" -Sq "${aur_flags[@]}" "${missing[@]}"; then
      logfile="${HOME}/Desktop/failed_packages.log"
      die "Batch install failed. Logging missing packages to ${logfile}"
      rm -f "$logfile"
      for p in "${missing[@]}"; do
        ! "${pkgmgr[@]}" -Qiq "$p" &>/dev/null && echo "$p" >> "$logfile"
      done
    else
      log "Installation complete"
    fi
  else
    # pacman only
    if ! "${pkgmgr[@]}" -Sq --needed --noconfirm "${missing[@]}"; then
      die "Pacman install failed. Check output"
    else
      log "Installation complete"
    fi
  fi
fi

# Flatpak apps
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo||:
  flats=(io.github.wiiznokes.fan-control)
  [[ ${#flats[@]} -gt 0 ]] && flatpak install -y flathub "${flats[@]}"||:
  flatpak update -y --noninteractive||:
fi

# Rust + Cargo utilities
if ! has rustup; then
  HotMsg "Installing rustup (minimal nightly)..."
  tmp=$(mktemp)
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > "$tmp"
  sh "$tmp" --profile minimal --default-toolchain nightly -y -q \
    -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy
  rm "$tmp"
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

rust_crates=(rmz cpz xcp crabz parallel-sh parel ffzap cargo-diet crab-fetch cargo-list 
  minhtml cargo-minify rimage ripunzip terminal_tools imagineer docker-image-pusher 
  image-optimizer dui-cli imgc pixelsqueeze bgone dupimg simagef compresscli dssim
  img-squeeze lq)

has sccache && export RUSTC_WRAPPER=sccache
rustup default nightly >/dev/null || :
rustup set auto-self-update disable || :
rustup set profile minimal || :
rustup self upgrade-data || :

# Install gitoxide with specific flags
LC_ALL=C cargo +nightly -Zgit -Zno-embed-metadata -Zbuild-std=std,panic_abort \
  -Zbuild-std-features=panic_immediate_abort install \
  --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins \
  --no-default-features --locked --features max-pure || :

# Install other Rust crates
[[ ${#rust_crates[@]} -gt 0 ]] && printf '%s\n' "${rust_crates[@]}"|xargs -P"$jobs" -I{} \
  LC_ALL=C cargo +nightly install -Zunstable-options -Zgit -Zgitoxide -Zavoid-dev-deps -Zno-embed-metadata --locked {} -f -q||:

# Micro plugins
if has micro; then
  mplug=(fish fzf wc filemanager cheat linter lsp autofmt detectindent editorconfig
    misspell comment diff jump bounce autoclose manipulator joinLines literate 
    status ftoptions)
  micro -plugin install "${mplug[@]}" || :
  micro -plugin update &>/dev/null || :
fi

# GitHub CLI extensions
has gh || sudo pacman -Sq github-cli --noconfirm --needed
if has gh; then
  gh extension install gennaro-tedesco/gh-f || :
  gh extension install gennaro-tedesco/gh-s || :
fi

# Go tools
has go || sudo pacman -Sq go --noconfirm --needed
has go && go install github.com/dim-an/cod@latest || :

# SDK tools and mise
if ! has mise; then
  HotMsg "Installing mise version manager..."
  curl -fsSL https://mise.jdx.dev/install.sh | sh || :
fi

if has sdk; then
  HotMsg "Installing GraalVM EE 25 via sdkman..."
  sdk install java 25-graal || :
fi

# Soar
curl -fsSL "https://raw.githubusercontent.com/pkgforge/soar/main/install.sh" | sh || :

# Housekeeping & system updates
has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry \
  '(-disable={config_update,system,tldr,maza,yazi,micro})' &>/dev/null || :
has fc-cache && sudo fc-cache -f &>/dev/null || :
has update-desktop-database && sudo update-desktop-database &>/dev/null || :
has fwupdmgr && { sudo fwupdmgr refresh -y && sudo fwupdtool update; } || :

# Initramfs
if has update-initramfs; then 
  sudo update-initramfs || :
elif has limine-mkinitcpio; then 
  sudo limine-mkinitcpio || :
elif has mkinitcpio; then 
  sudo mkinitcpio -P || :
elif has /usr/lib/booster/regenerate_images; then 
  sudo /usr/lib/booster/regenerate_images || :
elif has dracut-rebuild; then 
  sudo dracut-rebuild || :
else 
  HotMsg "⚠ initramfs generator not found; update manually"
fi

# Cleanup
orphans="$(pacman -Qdtq 2>/dev/null || :)"
[[ -n "$orphans" ]] && sudo pacman -Rns $orphans --noconfirm &>/dev/null || :
sudo pacman -Sccq --noconfirm &>/dev/null || :
[[ "${is_aur_helper:-0}" -eq 1 ]] && "${pkgmgr[@]}" -Sccq --noconfirm &>/dev/null || :
sudo journalctl --rotate --vacuum-size=1 --flush --sync -q || :
sudo fstrim -a --quiet-unsupported || :
# Shell integration setup for common shells
HotMsg "Setting up shell integration..."

fish_setup(){
  mkdir -p "$HOME/.config/fish/conf.d" || :
  fish -c "fish_update_completions" || :
  if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
    fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher update"
    fishplug=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache
    oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper 
    scaryrawr/cheat.sh.fish y3owk1n/fish-x
    scaryrawr/zoxide kpbaks/autols.fish patrickf1/fzf.fish
    jorgebucaran/autopair.fish wawa19933/fish-systemd
    halostatue/fish-rust kpbaks/zellij.fish)
    printf '%s\n' "${fishplug[@]}" | fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher install " || :
  fi
}
# Bash setup
bash_setup(){
  mkdir -p "${HOME}/.config/bash" || :
  curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" \
    -o "${HOME}/.config/bash/fzf-simple-completion.sh" && chmod +x "${HOME}/.config/bash/fzf-simple-completion.sh"
}
zsh_setup(){
  if [[ ! -f "$HOME/.p10k.zsh" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-lean.zsh" \
      -o "$HOME/.p10k.zsh" || :
  fi
  [[ ! -f "$HOME/.zshenv" ]] && echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
  mkdir -p "$HOME/.config/zsh" || :
  if [[ ! -d "$HOME/.local/share/zinit/zinit.git" ]]; then
    mkdir -p "$HOME/.local/share/zinit" || :
    git clone https://github.com/zdharma-continuum/zinit.git "$HOME/.local/share/zinit/zinit.git" || :
  fi
}

declare -A shell_setups=(
  [zsh]='zsh_setup'
  [fish]='fish_setup'
  [bash]='bash_setup'
)
for sh in "${!shell_setups[@]}"; do
  has "$sh" && eval "${shell_setups[$sh]}" ||:
done

log "All done! Restart your shell to apply all changes."
