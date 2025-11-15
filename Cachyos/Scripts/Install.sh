#!/usr/bin/env bash -euo pipefail
shopt -s nullglob globstar; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}" SHELL="$(command -v bash &>/dev/null)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$CRIPTDIR"
#============ Core Helper Functions ============
has(){ command -v "$1" &>/dev/null; }
have(){ command -v "$1" 2>/dev/null; }
[[ -r "${SCRIPT_DIR}/../lib/common.sh" ]] && source "${SCRIPT_DIR}/../lib/common.sh" || exit 1
# Custom msg functions for this script
msg(){ printf '%b\n' "$*"; }
die(){ msg "$'\e[31m'Error:$'\e[0m' $*" >&2; exit "${2:-1}"; }
# Package manager detection
if has paru; then pkgmgr=(paru) aur=1
else pkgmgr=(sudo pacman) aur=0
fi
# Additional build environment settings specific to this script
jobs=$(nproc 2>/dev/null || echo 4)
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf &>/dev/null
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true RUSTFLAGS="${RUSTFLAGS:-'-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols'}" \
  OPT_LEVEL=3 CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_OPT_LEVEL=3 UV_COMPILE_BYTECODE=1  PYTHONOPTIMIZE=2
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER PYTHONDONTWRITEBYTECODE
# System preparation
localectl set-locale C.UTF-8
sudo chmod -R 744 ~/.ssh; sudo chmod -R 744 ~/.gnupg
ssh-keyscan -H aur.archlinux.org >> ~/.ssh/known_hosts; ssh-keyscan -H github.com >> ~/.ssh/known_hosts
sudo chown -c root:root /etc/doas.conf; sudo chmod -c 0400 /etc/doas.conf
sudo modprobe zram tcp_bbr adios
[[ -f /var/lib/pacman/db.lck ]] && sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :
sudo pacman-key --init
sudo pacman-key --populate archlinux cachyos; sudo pacman -Sy archlinux-keyring cachyos-keyring --noconfirm || :
sudo pacman -Syyu --noconfirm || :

# Package list
pkgs=(git curl wget rsync patchutils ccache sccache mold lld llvm clang nasm yasm openmp
  "${aur:+}" paru polly optipng svgo graphicsmagick yadm mise micro hyfetch polkit-kde-agent
  pigz lrzip pixz plzip lbzip2 pbzip2 minizip-ng zstd lz4 xz bleachbit bleachbit-admin cleanerml-git
  preload irqbalance auto-cpufreq thermald cpupower cpupower-gui zoxide starship openrgb
  profile-sync-daemon profile-cleaner prelockd uresourced modprobed-db cachyos-ksm-settings
  cachyos-settings autofdo-bin vulkan-mesa-layers vkd3d vkd3d-proton-git mesa-utils vkbasalt
  menu-cache plasma-wayland-protocols xdg-desktop-portal xdg-desktop-portal-kde xorg-xhost
  libappindicator-gtk3 libdbusmenu-glib appmenu-gtk-module protonup-qt protonplus proton-ge-custom
  gamemode lib32-gamemode mangohud lib32-mangohud prismlauncher obs-studio luxtorpeda-git
  dxvk-gplasync-bin rustup python-pip uv github-cli bun-bin cod-bin biome yamlfmt
  eza bat fd ripgrep sd dust skim fzf shfmt shellcheck shellharden fastfetch cachyos-gaming-applications
  pay-respects fclones topgrade bauh flatpak partitionmanager kbuilder
  cleanlib32 multipath-tools sshpass cpio bc fuse2 appimagelauncher xdg-ninja cylon
  makepkg-optimize-mold usb-dirty-pages-udev unzrip-git adbr-git av1an jdk-temurin jdk25-graalvm-bin
  vscodium-electron vk-hdr-layer-kwin6-git soar zoi-bin cargo-binstall cargo-edit cargo-c cargo-update cargo-outdated
  cargo-make cargo-llvm-cov cargo-cache cargo-machete cargo-pgo cargo-binutils cargo-udeps cargo-pkgbuild
)
# Install packages
mapfile -t inst < <(pacman -Qq 2>/dev/null)
declare -A have; for p in "${inst[@]}"; do have[$p]=1; done
miss=(); for p in "${pkgs[@]}"; do [[ -n ${have[$p]} ]] || miss+=("$p"); done
if (( ${#miss[@]} )); then
  msg "Installing ${#miss[@]} pkgs"
  if (( aur )); then
    paru -Sq --needed --noconfirm --sudoloop --skipreview --batchinstall --nocheck --mflags '--nocheck --skipinteg --skippgpcheck --skipchecksums' \
      --gpgflags '--batch -q --yes --skip-verify' --cleanafter --removemake "${miss[@]}" 2>/dev/null || {
      msgfile="${HOME}/failed_pkgs.msg"; msg "Batch failed → $msgfile"; rm -f "$msgfile"
      for p in "${miss[@]}"; do paru -Qi "$p" 2>/dev/null || echo "$p" >> "$msgfile"; done; }
  else
    sudo pacman -Sq --needed --noconfirm --disable-download-timeout "${miss[@]}" 2>/dev/null || die "Install failed"
  fi
fi

# Flatpak setup
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null || :
  flats=(io.github.wiiznokes.fan-control)
  (( ${#flats[@]} )) && flatpak install -y flathub "${flats[@]}" 2>/dev/null || :
  flatpak update -y --noninteractive 2>/dev/null || :
fi

# Rustup setup
if ! has rustup; then
  msg "Installing rustup"
  local tmp=$(mktemp)
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > "$tmp"
  bash "$tmp" --profile minimal --default-toolchain nightly -y -q -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy 2>/dev/null; rm "$tmp"
  export PATH="$HOME/.cargo/bin:$PATH"
else
  rustup default nightly 2>/dev/null || :
  rustup set profile minimal 2>/dev/null || :
  rustup self upgrade-data 2>/dev/null || :
  rustup update 2>/dev/null || :
  has sccache && export RUSTC_WRAPPER=sccache
fi

# Cargo utilities
crates=(
  cpz xcp crabz rmz parel ffzap cargo-binstall cargo-diet crab-fetch cargo-list minhtml cargo-minify
  rimage ripunzip terminal_tools imagineer docker-image-pusher image-optimizer dui-cli imgc pixelsqueeze
  bgone dupimg simagef compresscli dssim img-squeeze lq parallel-sh frep dupe-krill bssh vicut aq-cli
)
if has cargo; then
  msg "Installing Rust utils"
  cargo install cargo-binstall -q 2>/dev/null || :
  # gitoxide with max optimizations
  # cargo install --git https://github.com/GitoxideLabs/gitoxide gitoxide -f --bins --features max-pure --no-default-features
  # Crate install
  cargo install -Zunstable-options -Zgit -Zgitoxide -Zavoid-dev-deps -Zno-embed-metadata --locked -f "${crates[@]}" 2>/dev/null || cargo binstall -y "${crates[@]}"
}

# Micro editor plugins
if has micro; then
  mplug=(fish fzf wc filemanager cheat linter lsp autofmt detectindent editorconfig misspell comment diff
    jump bounce autoclose manipulator joinLines literate status ftoptions)
  micro -plugin install "${mplug[@]}" 2>/dev/null &
  micro -plugin update 2>/dev/null &
fi

# GitHub CLI extensions
if has gh; then
  gh_exts=(gennaro-tedesco/gh-f gennaro-tedesco/gh-s seachicken/gh-poi redraw/gh-install k1LoW/gh-grep
    2KAbhishek/gh-repo-man HaywardMorihara/gh-tidy gizmo385/gh-lazy)
  msg "Installing gh extensions"
  gh extension install "${gh_exts[@]}" 2>/dev/null || :
fi

if has mise; then
  msg "Configuring mise"
  mise settings set experimental true; mise trust
  local -a ms_tools=()
  mise use -g "${ms_tools[@]}" 2>/dev/null || :
  mise doctor
fi

# sdkman (Java version manager)
if [[ ! -d "$HOME/.sdkman" ]]; then
  msg "Installing sdkman"
  curl -sf "https://get.sdkman.io?ci=true" | bash 2>/dev/null || :
  export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
else
  export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
  msg "Configuring sdkman"
  sdk selfupdate 2>/dev/null
  sdk update 2>/dev/null
fi

# soar package manager
if has soar; then
  msg "Configuring soar"
  soar self update
  soar S && soar u --no-verify
  soar_pkgs=()
  for pkg in "${soar_pkgs[@]}"; do 
    soar s "$pkg" && soar i -yq "$pkg" || { soar ls 2>/dev/null | grep -q "$pkg" || soar i -yq "$pkg"; }
  done
  soar i -yq 'sstrip.upx.ss#github.com.pkgforge-dev.super-strip'
fi

# Shell integration
fish_setup(){
  mkdir -p "${HOME}/.config/fish/conf.d"
  fish -c "fish_update_completions"
  if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
    fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher update" 2>/dev/null &
    fishplug=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache
      oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x scaryrawr/zoxide
      kpbaks/autols.fish patrickf1/fzf.fish jorgebucaran/autopair.fish wawa19933/fish-systemd
      halostatue/fish-rust kpbaks/zellij.fish); wait
    printf '%s\n' "${fishplug[@]}" | fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher install" 2>/dev/null || :
  fi
}
zsh_setup(){
  [[ ! -f "${HOME}/.zshenv" ]] && echo 'export ZDOTDIR="$HOME/.config/zsh"' > "${HOME}/.zshenv"
  mkdir -p "${HOME}/.config/zsh"
  [[ ! -d "${HOME}/.local/share/antidote" ]] && git clone --depth=1 --filter=blob:none https://github.com/mattmc3/antidote.git "${HOME}/.local/share/antidote"
}
declare -A shell_setups=([zsh]=zsh_setup [fish]=fish_setup
for sh in "${!shell_setups[@]}"; do
  has "$sh" && "${shell_setups[$sh]}" &
done

# Enable services
srvc=(irqbalance prelockd memavaild uresourced preload pci-latency)
for sv in "${srvc[@]}"; do 
  sudo systemctl is-enabled "$svc" || sudo systemctl enable --now "$sv"
done
wait

# System maintenance
has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry \
  '(-disable={config_update,system,tldr,maza,yazi,micro})' 2>/dev/null || :
has fc-cache && sudo fc-cache -f
has update-desktop-database && sudo update-desktop-database
has fwupdmgr && { sudo fwupdmgr refresh -y 2>/dev/null; sudo fwupdtool update; } || :

# Initramfs rebuild
if has update-initramfs; then
  sudo update-initramfs || :
elif has limine-mkinitcpio; then
  sudo limine-mkinitcpio || :
elif has mkinitcpio; then
  sudo mkinitcpio -P || :
elif [[ -x /usr/lib/booster/regenerate_images ]]; then
  sudo /usr/lib/booster/regenerate_images || :
elif has dracut-rebuild; then
  sudo dracut-rebuild || :
else
  msg "⚠ initramfs generator not found"
fi

# Cleanup
sudo pacman -Rns --noconfirm "$(pacman -Qdtq 2>/dev/null)" 2>/dev/null || :
paru -Scc --noconfirm || sudo pacman -Scc --noconfirm
(( aur )) && "${pkgmgr[@]}" -Sccq --noconfirm 2>/dev/null || :
sudo journalctl --rotate -q; sudo journalctl --rotate --vacuum-size=50M -q
sudo fstrim -a

msg "Setup complete! Restart shell."
[[ -f "${HOME}/failed_pkgs.msg" ]] && msg "⚠ Check ~/failed_pkgs.msg"
