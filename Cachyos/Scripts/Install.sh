#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null || :
jobs=$(nproc)
has(){ command -v "$1" &>/dev/null; }
msg(){ printf '\e[1;33m▶ %s\e[0m\n' "$*"; }
die(){ printf '\e[1;31m✖ %s\e[0m\n' "$*" >&2; exit "${2:-1}"; }
log(){ printf '\e[1;36m✓ %s\e[0m\n' "$*"; }
get_priv(){ for cmd in sudo-rs sudo doas; do has "$cmd" && { echo "$cmd"; return 0; }; done; [[ $EUID -eq 0 ]] || die "No priv" 1; }
PRIV=$(get_priv); [[ -n $PRIV && $EUID -ne 0 ]] && "$PRIV" -v
run_priv(){ [[ $EUID -eq 0 || -z $PRIV ]] && "$@" || "$PRIV" -- "$@"; }
if has paru; then pkgmgr=(paru) aur=1; elif has yay; then pkgmgr=(yay) aur=1; else pkgmgr=(pacman) aur=0; fi
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf
: "${CFLAGS:=-O3 -march=native -mtune=native -pipe}" "${CXXFLAGS:=$CFLAGS}"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib MAKEFLAGS="-j$jobs" NINJAFLAGS="-j$jobs" \
  GOMAXPROCS="$jobs" CARGO_BUILD_JOBS="$jobs" CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true \
  OPT_LEVEL=3 CARGO_INCREMENTAL=0 RUSTC_BOOTSTRAP=1 CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
  CARGO_PROFILE_RELEASE_OPT_LEVEL=3 UV_COMPILE_BYTECODE=1 UV_NO_VERIFY_HASHES=1 UV_SYSTEM_PYTHON=1 \
  UV_FORK_STRATEGY=fewest UV_RESOLUTION=highest ZSTD_NBTHREADS=0 FLATPAK_FORCE_TEXT_AUTH=1 PYTHONOPTIMIZE=2 \
  PYTHON_JIT=1 ELECTRON_OZONE_PLATFORM_HINT=auto
: "${RUSTFLAGS:=-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clinker-plugin-lto \
-Cllvm-args=-enable-dfa-jump-thread -Clinker=clang -Clink-arg=-fuse-ld=lld -Zunstable-options -Ztune-cpu=native \
-Zfunction-sections -Zfmt-debug=none -Zlocation-detail=none}"
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER PYTHONDONTWRITEBYTECODE
run_priv rm -f /var/lib/pacman/db.lck 2>/dev/null || :
run_priv pacman-key --init 2>/dev/null || :
run_priv pacman-key --populate archlinux cachyos 2>/dev/null || :
"${pkgmgr[@]}" -Syq archlinux-keyring cachyos-keyring --noconfirm 2>/dev/null || :
"${pkgmgr[@]}" -Syyuq --noconfirm 2>/dev/null || :
pkgs=(
  base-devel linux-headers dkms git curl wget rsync patchutils
  "${aur:+}" paru yay ccache sccache mold lld llvm clang nasm yasm openmp polly
  pigz lrzip pixz plzip lbzip2 pbzip2 minizip-ng zstd lz4 xz optipng svgo graphicsmagick
  preload irqbalance ananicy-cpp auto-cpufreq thermald cpupower cpupower-gui openrgb
  profile-sync-daemon profile-cleaner prelockd uresourced modprobed-db cachyos-ksm-settings
  cachyos-settings autofdo-bin vulkan-mesa-layers vkd3d vkd3d-proton-git mesa-utils vkbasalt
  menu-cache plasma-wayland-protocols xdg-desktop-portal xdg-desktop-portal-kde xorg-xhost
  libappindicator-gtk3 libdbusmenu-glib appmenu-gtk-module protonup-qt protonplus proton-ge-custom
  gamemode lib32-gamemode mangohud lib32-mangohud prismlauncher obs-studio luxtorpeda-git
  dxvk-gplasync-bin rustup jdk24-graalvm-ee-bin python-pip uv github-cli bun-bin starship zoxide
  eza bat fd ripgrep sd dust fzf shfmt shellcheck shellharden micro yadm dash btop htop fastfetch
  pay-respects fclones topgrade bauh flatpak partitionmanager polkit-kde-agent bleachbit-git
  cleanlib32 multipath-tools sshpass cpio bc fuse2 appimagelauncher cleanerml-git
  makepkg-optimize-mold usb-dirty-pages-udev unzrip-git adbr-git av1an xdg-ninja cylon
  scaramanga kbuilder optiimage optipng-parallel
)
mapfile -t inst < <(pacman -Qq 2>/dev/null)
declare -A have; for p in "${inst[@]}"; do have[$p]=1; done
miss=(); for p in "${pkgs[@]}"; do [[ -n ${have[$p]} ]] || miss+=("$p"); done
if (( ${#miss[@]} )); then
  msg "Installing ${#miss[@]} pkgs"
  if (( aur )); then
    "${pkgmgr[@]}" -Sq --needed --noconfirm --removemake --cleanafter --sudoloop --skipreview --nokeepsrc \
      --batchinstall --combinedupgrade --mflags '--cleanbuild --clean --rmdeps --syncdeps --nocheck --skipinteg --skippgpcheck --skipchecksums' \
      --gitflags '--depth=1' --gpgflags '--batch -q -z1 --yes --skip-verify' "${miss[@]}" 2>/dev/null || {
      logfile="$HOME/Desktop/failed_pkgs.log"; msg "Batch failed → $logfile"; rm -f "$logfile"
      for p in "${miss[@]}"; do "${pkgmgr[@]}" -Qi "$p" &>/dev/null || echo "$p" >> "$logfile"; done; }
  else run_priv pacman -Sq --needed --noconfirm "${miss[@]}" 2>/dev/null || die "Install failed"; fi
  log "Packages ✓"
else log "All packages ✓"; fi
for svc in preload irqbalance ananicy-cpp auto-cpufreq thermald; do
  has "$svc" && run_priv systemctl is-enabled "$svc" &>/dev/null || run_priv systemctl enable --now "$svc" 2>/dev/null || :
done &
if has flatpak; then
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || :
  flats=(io.github.wiiznokes.fan-control); (( ${#flats[@]} )) && flatpak install -y flathub "${flats[@]}" 2>/dev/null || :
  flatpak update -y --noninteractive 2>/dev/null || :
fi &
if ! has rustup; then
  msg "Installing rustup"; tmp=$(mktemp); curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > "$tmp"
  sh "$tmp" --profile minimal --default-toolchain nightly -y -q -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy 2>/dev/null
  rm "$tmp"; export PATH="$HOME/.cargo/bin:$PATH"
fi
has rustup && { rustup default nightly 2>/dev/null || :; rustup set auto-self-update disable 2>/dev/null || :
  rustup set profile minimal 2>/dev/null || :; rustup self upgrade-data 2>/dev/null || :
  has sccache && export RUSTC_WRAPPER=sccache; } &
crates=(cpz xcp crabz rmz parel ffzap cargo-binstall cargo-diet crab-fetch cargo-list minhtml cargo-minify
  rimage ripunzip terminal_tools imagineer docker-image-pusher image-optimizer dui-cli imgc pixelsqueeze
  bgone dupimg simagef compresscli dssim img-squeeze lq parallel-sh)
has cargo && { msg "Installing Rust utils"; cargo install cargo-binstall -q 2>/dev/null || :
  LC_ALL=C cargo +nightly -Zgit -Zno-embed-metadata -Zbuild-std=std,panic_abort \
    -Zbuild-std-features=panic_immediate_abort install --git https://github.com/GitoxideLabs/gitoxide \
    gitoxide -f --bins --no-default-features --locked --features max-pure 2>/dev/null || : &
  printf '%s\n' "${crates[@]}" | xargs -P"$jobs" -I{} sh -c \
    'cargo install --list 2>/dev/null | grep -q "^{} " || cargo binstall -y {} 2>/dev/null || \
     LC_ALL=C cargo +nightly install -Zunstable-options -Zgit -Zgitoxide -Zavoid-dev-deps \
     -Zno-embed-metadata --locked {} -f -q 2>/dev/null || :' &; } &
if has micro; then
  mplug=(fish fzf wc filemanager cheat linter lsp autofmt detectindent editorconfig misspell comment diff
    jump bounce autoclose manipulator joinLines literate status ftoptions)
  micro -plugin install "${mplug[@]}" 2>/dev/null &; micro -plugin update 2>/dev/null &
fi &
has gh || run_priv pacman -Sq github-cli --noconfirm --needed 2>/dev/null
if has gh; then
  gh_exts=(gennaro-tedesco/gh-f gennaro-tedesco/gh-s seachicken/gh-poi redraw/gh-install k1LoW/gh-grep
    2KAbhishek/gh-repo-man HaywardMorihara/gh-tidy gizmo385/gh-lazy); msg "Installing gh extensions"
  printf '%s\n' "${gh_exts[@]}" | xargs -P"$jobs" -I{} sh -c \
    'gh extension list 2>/dev/null | grep -q "{}" || gh extension install {} 2>/dev/null || :' &
fi &
if ! has mise; then msg "Installing mise"; curl -fsSL https://mise.jdx.dev/install.sh | sh 2>/dev/null || :
  export PATH="$HOME/.local/bin:$PATH"; fi
if has mise; then msg "Configuring mise"; mise settings set experimental true 2>/dev/null || :
  mise trust 2>/dev/null || :; mise install 2>/dev/null || :
  for tool in node@lts python@latest go@latest bun@latest pnpm@latest fnm@latest; do
    mise use -g "$tool" 2>/dev/null || :; done
  mise doctor 2>/dev/null || :; has go && go install github.com/dim-an/cod@latest 2>/dev/null || :
fi
if [[ ! -d "$HOME/.sdkman" ]]; then msg "Installing sdkman"
  curl -sf "https://get.sdkman.io?ci=true" | bash 2>/dev/null || :; export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi
if [[ -d "$HOME/.sdkman" ]]; then 
  export SDKMAN_DIR="$HOME/.sdkman"
  [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
  msg "Configuring sdkman"
  sdk selfupdate 2>/dev/null; sdk update 2>/dev/null
fi
if ! has soar; then msg "Installing soar"
  curl -fsL "https://raw.githubusercontent.com/pkgforge/soar/main/install.sh" | sh 2>/dev/null || :
  export PATH="$HOME/.local/share/soar/bin:$PATH"; fi
if has soar; then
  msg "Configuring soar"
  soar self update || :
  soar S && soar u --no-verify || :
  soar_pkgs=()
  for pkg in "${soar_pkgs[@]}"; do 
    soar s "$pkg" && soar i -yq "$pkg" || : 
    soar ls 2>/dev/null | grep -q "$pkg" || soar i -yq "$pkg" || : 
  done
  soar i -yq 'sstrip.upx.ss#github.com.pkgforge-dev.super-strip'
fi


fish_setup(){ mkdir -p "$HOME/.config/fish/conf.d" 2>/dev/null || :
  fish -c "fish_update_completions" 2>/dev/null || :
  if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
    fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher update" 2>/dev/null &
    fishplug=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache
      oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x scaryrawr/zoxide
      kpbaks/autols.fish patrickf1/fzf.fish jorgebucaran/autopair.fish wawa19933/fish-systemd
      halostatue/fish-rust kpbaks/zellij.fish)
    printf '%s\n' "${fishplug[@]}" | fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher install" 2>/dev/null || :
  fi; }
bash_setup(){ mkdir -p "$HOME/.config/bash" 2>/dev/null || :
  curl -fsSL "https://raw.githubusercontent.com/duong-db/fzf-simple-completion/refs/heads/main/fzf-simple-completion.sh" \
    -o "$HOME/.config/bash/fzf-simple-completion.sh" && chmod +x "$_" 2>/dev/null; }
zsh_setup(){ [[ ! -f "$HOME/.p10k.zsh" ]] && curl -fsSL \
    "https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-lean.zsh" -o "$HOME/.p10k.zsh" 2>/dev/null || :
  [[ ! -f "$HOME/.zshenv" ]] && echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
  mkdir -p "$HOME/.config/zsh" "$HOME/.local/share/zinit" 2>/dev/null || :
  [[ ! -d "$HOME/.local/share/zinit/zinit.git" ]] && git clone --depth=1 \
    https://github.com/zdharma-continuum/zinit.git "$HOME/.local/share/zinit/zinit.git" 2>/dev/null || :; }
declare -A shell_setups=([zsh]=zsh_setup [fish]=fish_setup [bash]=bash_setup)
for sh in "${!shell_setups[@]}"; do has "$sh" && "${shell_setups[$sh]}" &; done
wait
has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry \
  '(-disable={config_update,system,tldr,maza,yazi,micro})' 2>/dev/null || : &
has fc-cache && run_priv fc-cache -f 2>/dev/null &
has update-desktop-database && run_priv update-desktop-database 2>/dev/null &
has fwupdmgr && { run_priv fwupdmgr refresh -y 2>/dev/null; run_priv fwupdtool update 2>/dev/null; } || : &
if has update-initramfs; then run_priv update-initramfs 2>/dev/null || :
elif has limine-mkinitcpio; then run_priv limine-mkinitcpio 2>/dev/null || :
elif has mkinitcpio; then run_priv mkinitcpio -P 2>/dev/null || :
elif has /usr/lib/booster/regenerate_images; then run_priv /usr/lib/booster/regenerate_images 2>/dev/null || :
elif has dracut-rebuild; then run_priv dracut-rebuild 2>/dev/null || :
else msg "⚠ initramfs generator not found"; fi &
wait
orphans=$(pacman -Qdtq 2>/dev/null || :)
[[ -n $orphans ]] && run_priv pacman -Rns "$orphans" --noconfirm 2>/dev/null || :
run_priv pacman -Sccq --noconfirm 2>/dev/null || :
(( aur )) && "${pkgmgr[@]}" -Sccq --noconfirm 2>/dev/null || :
run_priv journalctl --rotate --vacuum-size=50M --flush --sync -q 2>/dev/null || :
run_priv fstrim -av 2>/dev/null || :
log "Setup complete! Restart shell."
[[ -f "$HOME/Desktop/failed_pkgs.log" ]] && msg "⚠ Check ~/Desktop/failed_pkgs.log"
