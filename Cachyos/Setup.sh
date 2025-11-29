#!/usr/bin/env bash
# Optimized: 2025-11-29 - Merged AutoSetup.sh into Setup.sh
set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
#──────────── Colors ────────────
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'
#──────────── Helpers ────────────
has(){ command -v "$1" &>/dev/null; }
msg(){ printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
warn(){ printf '%b%s%b\n' "$YLW" "$*" "$DEF"; }
die(){
  printf '%b%s%b\n' "$RED" "$*" "$DEF" >&2
  exit "${2:-1}"
}
#──────────── Setup ────────────
if has paru; then
  pkgmgr=(paru) aur=1
else
  pkgmgr=(sudo pacman) aur=0
fi

#──────────── Build Environment ────────────
jobs=$(nproc 2>/dev/null || echo 4)
[[ -r /etc/makepkg.conf ]] && . /etc/makepkg.conf &>/dev/null
export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true \
  RUSTFLAGS="${RUSTFLAGS:-'-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols'}" \
  OPT_LEVEL=3 CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 CARGO_PROFILE_RELEASE_OPT_LEVEL=3 \
  UV_COMPILE_BYTECODE=1 PYTHONOPTIMIZE=2
unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER PYTHONDONTWRITEBYTECODE

#══════════════════════════════════════════════════════════════
#  REPOSITORY CONFIGURATION
#══════════════════════════════════════════════════════════════
setup_repositories(){
  local -r conf=/etc/pacman.conf
  local -r chaotic_key=3056513887B78AEB
  local -a chaotic_urls=(
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  )
  has_repo(){ grep -qF -- "$1" "$conf"; }
  add_block(){ printf '%s\n' "$1" | sudo tee -a "$conf" >/dev/null; }
  # Chaotic-AUR
  if ! has_repo '[chaotic-aur]'; then
    msg "Adding chaotic-aur repo"
    sudo pacman-key --keyserver keyserver.ubuntu.com -r "$chaotic_key" &>/dev/null || :
    yes | sudo pacman-key --lsign-key "$chaotic_key" &>/dev/null || :
    sudo pacman --noconfirm --needed -U "${chaotic_urls[@]}" &>/dev/null || :
    add_block '[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist'
  fi
  # Artafinde
  if ! has_repo '[artafinde]'; then
    msg "Adding artafinde repo"
    add_block '[artafinde]
Server = https://pkgbuild.com/~artafinde/repo'
  fi
  # ALHP (x86-64-v3 optimized)
  if ! has_repo '[core-x86-64-v3]'; then
    msg "Adding ALHP repos"
    if ((aur)); then
      paru --noconfirm --skipreview --needed -S alhp-keyring alhp-mirrorlist &>/dev/null || :
    else
      sudo pacman --noconfirm --needed -S alhp-keyring alhp-mirrorlist &>/dev/null || :
    fi
    add_block '[core-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[core]
Include = /etc/pacman.d/mirrorlist

[extra-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist

[multilib-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist'
  fi
  # EndeavourOS
  if ! has_repo '[endeavouros]'; then
    msg "Adding EndeavourOS repo"
    local tmp
    tmp=$(mktemp -d)
    local repo=https://github.com/endeavouros-team/PKGBUILDS.git
    if has gix; then
      gix clone --depth=1 --no-tags "$repo" "$tmp" &>/dev/null
    else
      git clone --depth=1 --filter=blob:none --no-tags "$repo" "$tmp" &>/dev/null
    fi
    for d in endeavouros-keyring endeavouros-mirrorlist; do
      (cd "$tmp/$d" && makepkg -sirc --skippgpcheck --skipchecksums --skipinteg --nocheck --noconfirm --needed &>/dev/null)
    done
    rm -rf "$tmp"
    add_block '[endeavouros]
SigLevel = Optional TrustAll
Include = /etc/pacman.d/endeavouros-mirrorlist'
  fi
  # CachyOS
  if ! pacman -Qq cachyos-mirrorlist &>/dev/null; then
    msg "Adding CachyOS repo"
    local tmp
    tmp=$(mktemp -d)
    (cd "$tmp" && curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o repo.tar.xz \
      && tar xf repo.tar.xz && cd cachyos-repo && chmod +x cachyos-repo.sh \
      && sudo bash cachyos-repo.sh) || warn "CachyOS repo setup failed"
    rm -rf "$tmp"
  fi
  # Sync if repos were added
  sudo pacman -Syy --noconfirm &>/dev/null || :
}

#══════════════════════════════════════════════════════════════
#  SYSTEM INITIALIZATION
#══════════════════════════════════════════════════════════════
init_system(){
  msg "Initializing system"
  localectl set-locale C.UTF-8 >/dev/null
  [[ -d ~/.ssh ]] && chmod -R 700 ~/.ssh
  [[ -d ~/.gnupg ]] && chmod -R 700 ~/.gnupg
  ssh-keyscan -H aur.archlinux.org github.com >> ~/.ssh/known_hosts 2>/dev/null || :
  [[ -f /etc/doas.conf ]] && {
    sudo chown root:root /etc/doas.conf
    sudo chmod 0400 /etc/doas.conf
  }
  modprobed-db store &>/dev/null
  sudo modprobed-db store &>/dev/null
  sudo modprobe zram tcp_bbr kvm kvm-intel >/dev/null
  [[ -f /var/lib/pacman/db.lck ]] && sudo rm -f /var/lib/pacman/db.lck
  sudo pacman-key --init &>/dev/null
  sudo pacman-key --populate archlinux cachyos &>/dev/null
  sudo pacman -Sy archlinux-keyring cachyos-keyring --noconfirm 2>/dev/null
  sudo pacman -Syyu --noconfirm 2>/dev/null
}

#══════════════════════════════════════════════════════════════
#  PACKAGE INSTALLATION
#══════════════════════════════════════════════════════════════
install_packages(){
  local -a pkgs=(
    git curl wget rsync patchutils ccache sccache mold lld llvm clang nasm yasm openmp
    paru polly optipng svgo graphicsmagick yadm mise micro hyfetch polkit-kde-agent
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
    vscodium-electron vk-hdr-layer-kwin6-git soar zoi-bin cargo-binstall cargo-edit cargo-c cargo-update
    cargo-outdated cargo-make cargo-llvm-cov cargo-cache cargo-machete cargo-pgo cargo-binutils
    cargo-udeps cargo-pkgbuild simagef-bin crabz
  )
  msg "Checking packages"
  mapfile -t installed < <(pacman -Qq 2>/dev/null)
  declare -A have
  for p in "${installed[@]}"; do have[$p]=1; done
  local -a missing
  for p in "${pkgs[@]}"; do [[ -n ${have[$p]:-} ]] || missing+=("$p"); done
  ((${#missing[@]} == 0)) && {
    msg "All packages installed"
    return 0
  }
  msg "Installing ${#missing[@]} packages"
  if ((aur)); then
    paru -S --needed --noconfirm --sudoloop --skipreview --batchinstall --nocheck \
      --mflags '--nocheck --skipinteg --skippgpcheck --skipchecksums' \
      --gpgflags '--batch -q --yes --skip-verify' --cleanafter --removemake "${missing[@]}" 2>/dev/null || {
      local fail="${HOME}/failed_pkgs.txt"
      msg "Batch install failed → $fail"
      for p in "${missing[@]}"; do
        pacman -Qq "$p" &>/dev/null || printf '%s\n' "$p" >> "$fail"
      done
    }
  else
    sudo pacman -S --needed --noconfirm --disable-download-timeout "${missing[@]}" || die "Install failed"
  fi
}

#══════════════════════════════════════════════════════════════
#  FLATPAK
#══════════════════════════════════════════════════════════════
setup_flatpak(){
  has flatpak || return 0
  msg "Configuring Flatpak"
  flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo &>/dev/null || :
  local -a apps=(io.github.wiiznokes.fan-control)
  ((${#apps[@]})) && flatpak install -y flathub "${apps[@]}" 2>/dev/null || :
  flatpak update -y --noninteractive 2>/dev/null || :
}

#══════════════════════════════════════════════════════════════
#  RUST TOOLCHAIN
#══════════════════════════════════════════════════════════════
setup_rust(){
  if ! has rustup; then
    msg "Installing Rust"
    bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs)" -- -y --profile minimal -c rust-src,llvm-tools,llvm-bitcode-linker,rustfmt,clippy
    export PATH="$HOME/.cargo/bin:$PATH"
  else
    rustup default nightly &>/dev/null || :
    rustup set profile minimal &>/dev/null || :
    rustup self upgrade-data &>/dev/null || :
    rustup update 2>/dev/null || :
  fi
  has sccache && export RUSTC_WRAPPER=sccache
  # Cargo utilities
  has cargo || return 0
  msg "Installing Rust tools"
  local -a crates=()
  cargo install --locked -f "${crates[@]}" || cargo binstall -y "${crates[@]}" || :
}

#══════════════════════════════════════════════════════════════
#  EDITOR & SHELL TOOLS
#══════════════════════════════════════════════════════════════
setup_tools(){
  # Micro editor
  if has micro; then
    msg "Configuring micro"
    local -a plugins=(fish fzf wc filemanager linter lsp autofmt detectindent editorconfig misspell diff ftoptions literate status)
    micro -plugin install "${plugins[@]}" &>/dev/null &
    micro -plugin update &>/dev/null &
  fi
  # GitHub CLI
  if has gh; then
    msg "Installing gh extensions"
    local -a exts=(gennaro-tedesco/gh-f gennaro-tedesco/gh-s seachicken/gh-poi
      2KAbhishek/gh-repo-man HaywardMorihara/gh-tidy gizmo385/gh-lazy)
    gh extension install "${exts[@]}" 2>/dev/null || :
  fi
  # Mise
  if has mise; then
    msg "Configuring mise"
    mise settings set experimental true
    mise trust -y
    mise doctor -y
    mise up -y || :
  fi
  # SDKMAN
  if [[ ! -d "$HOME/.sdkman" ]]; then
    msg "Installing SDKMAN"
    bash -c "curl -fsSL 'https://get.sdkman.io?ci=true'"
  fi
  export SDKMAN_DIR="$HOME/.sdkman"
  if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    sdk selfupdate 2>/dev/null || :
    sdk update 2>/dev/null || :
  fi
  # Soar
  if has soar; then
    msg "Configuring soar"
    soar self update 2>/dev/null || :
    soar S &>/dev/null && soar u --no-verify &>/dev/null || :
    soar i -yq 'sstrip.upx.ss#github.com.pkgforge-dev.super-strip' 2>/dev/null || :
  fi
}

#══════════════════════════════════════════════════════════════
#  SHELL INTEGRATION
#══════════════════════════════════════════════════════════════
setup_shells(){
  # Fish
  if has fish; then
    msg "Configuring Fish shell"
    mkdir -p "$HOME/.config/fish/conf.d"
    fish -c "fish_update_completions" 2>/dev/null || :
    if [[ -r /usr/share/fish/vendor_functions.d/fisher.fish ]]; then
      fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher update" 2>/dev/null &
      local -a plugins=(acomagu/fish-async-prompt kyohsuke/fish-evalcache eugene-babichenko/fish-codegen-cache
        oh-my-fish/plugin-xdg wk/plugin-ssh-term-helper scaryrawr/cheat.sh.fish y3owk1n/fish-x scaryrawr/zoxide
        kpbaks/autols.fish patrickf1/fzf.fish jorgebucaran/autopair.fish wawa19933/fish-systemd
        halostatue/fish-rust kpbaks/zellij.fish)
      printf '%s\n' "${plugins[@]}" | fish -c "source /usr/share/fish/vendor_functions.d/fisher.fish && fisher install" 2>/dev/null &
    fi
  fi

  # Zsh
  if has zsh; then
    msg "Configuring Zsh"
    [[ -f "$HOME/.zshenv" ]] || echo 'export ZDOTDIR="$HOME/.config/zsh"' > "$HOME/.zshenv"
    mkdir -p "$HOME/.config/zsh"
    [[ -d "$HOME/.local/share/antidote" ]] \
      || git clone --depth=1 --filter=blob:none https://github.com/mattmc3/antidote.git "$HOME/.local/share/antidote" 2>/dev/null &
  fi
}

#══════════════════════════════════════════════════════════════
#  SYSTEM SERVICES
#══════════════════════════════════════════════════════════════
enable_services(){
  msg "Enabling services"
  local -a svcs=(irqbalance prelockd memavaild uresourced preload pci-latency)
  for sv in "${svcs[@]}"; do
    systemctl is-enabled "$sv" &>/dev/null || sudo systemctl enable --now "$sv" &>/dev/null || :
  done
}

#══════════════════════════════════════════════════════════════
#  SYSTEM MAINTENANCE
#══════════════════════════════════════════════════════════════
maintenance(){
  msg "Running maintenance"
  has topgrade && topgrade -cy --skip-notify --no-self-update --no-retry 2>/dev/null || :
  has fc-cache && sudo fc-cache -f || :
  has update-desktop-database && sudo update-desktop-database || :
  if has fwupdmgr; then
    sudo fwupdmgr refresh -y &>/dev/null || :
    sudo fwupdmgr update &>/dev/null || :
  fi

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
    warn "No initramfs generator found"
  fi
}

#══════════════════════════════════════════════════════════════
#  AUTO SETUP TWEAKS (Merged from AutoSetup.sh)
#══════════════════════════════════════════════════════════════
auto_setup_tweaks(){
  msg "Applying AutoSetup system tweaks"

  # Filesystem optimizations
  local root_dev fstype
  root_dev=$(findmnt -n -o SOURCE /)
  fstype=$(findmnt -n -o FSTYPE /)
  if [[ $fstype == "ext4" ]]; then
    msg "Applying ext4 fast_commit on $root_dev"
    sudo tune2fs -O fast_commit "$root_dev" 2>/dev/null || :
  else
    msg "Skipping tune2fs (filesystem: $fstype)"
  fi

  # KDE & Appearance
  if has kwriteconfig6; then
    msg "Applying Breeze Dark theme"
    kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark" 2>/dev/null || :
    has plasma-apply-desktoptheme && plasma-apply-desktoptheme breeze-dark 2>/dev/null || :
  fi

  # Alacritty config
  [[ -f "$HOME/.config/alacritty/alacritty.toml" ]] && sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

  # Locale fallback
  locale -a | grep -q '^en_US\.utf8$' && export LANG='en_US.UTF-8' LANGUAGE='en_US' || export LANG='C.UTF-8'

  # Debloat
  msg "Debloat and fixup"
  sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm &>/dev/null || :
  sudo pacman -Rns cachy-browser --noconfirm &>/dev/null || :

  # Basher
  if ! command -v basher &>/dev/null; then
    msg "Install basher"
    curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash
  fi

  # Optimize systemd config (Storage=none, etc.)
  msg "Optimize systemd writes"
  for svc in journald coredump; do
    local file="/etc/systemd/${svc}.conf"
    [[ -f $file ]] || continue
    local kvs=("Storage=none")
    [[ $svc == journald ]] && kvs+=("Seal=no" "Audit=no")
    for kv in "${kvs[@]}"; do
      local key="${kv%%=*}"
      if grep -qE "^#*${key}=" "$file"; then
        sudo sed -i -E "s|^#*${key}=.*|$kv|" "$file"
      else
        echo "$kv" | sudo tee -a "$file" >/dev/null
      fi
    done
  done

  # Bluetooth tweaks
  if [[ -f /etc/bluetooth/main.conf ]]; then
    msg "Tweaking Bluetooth config"
    sudo sed -i \
      -e 's/AutoEnable.*/AutoEnable = false/' \
      -e 's/FastConnectable.*/FastConnectable = false/' \
      -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' \
      -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' \
      /etc/bluetooth/main.conf
  fi
  sudo rm -rf /var/lib/bluetooth/* &>/dev/null || :

  # Systemd timeouts & ZRAM
  msg "Systemd timeouts & ZRAM"
  sudo sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
  sudo sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf
  if [[ -f /etc/default/zramswap ]]; then
    sudo sed -i -e 's/#ALGO.*/ALGO=lz4/g' -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap
  fi

  # Disable Plymouth & Baloo
  msg "Disable Plymouth & Baloo"
  sudo systemctl mask plymouth-{read-write,start,quit,quit-wait}.service &>/dev/null || :
  if has balooctl6; then
    balooctl6 suspend &>/dev/null || :
    balooctl6 disable &>/dev/null || :
    balooctl6 purge &>/dev/null || :
  fi
  sudo systemctl disable --now plasma-baloorunner &>/dev/null || :
  
  # Indexing barriers
  for dir in "$HOME" "$HOME"/*/; do 
    [[ -d $dir ]] && touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore" 2>/dev/null || :
  done

  # Write cache & Services
  msg "Enable write cache & Disable logs/services"
  echo "write back" | sudo tee /sys/block/*/queue/write_cache &>/dev/null || :
  
  sudo systemctl mask systemd-update-utmp{,-runlevel,-shutdown}.service systemd-journal-{flush,catalog-update}.service systemd-journald-{dev-log,audit}.socket &>/dev/null || :
  sudo systemctl disable --global speech-dispatcher smartmontools systemd-rfkill.{service,socket} &>/dev/null || :
  sudo systemctl disable speech-dispatcher smartmontools systemd-rfkill.{service,socket} &>/dev/null || :
  
  # Dbus-broker
  if systemctl list-unit-files dbus-broker.service &>/dev/null; then
    msg "Enable dbus-broker"
    sudo systemctl enable --global dbus-broker.service &>/dev/null || :
    sudo systemctl enable dbus-broker.service &>/dev/null || :
  fi

  # NetworkManager & Modprobe
  msg "Disable wait online & GPU polling"
  sudo mkdir -p /etc/NetworkManager/conf.d
  echo -e "[connectivity]\nenabled=false" | sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf >/dev/null
  sudo systemctl mask NetworkManager-wait-online.service systemd-networkd-wait-online.service &>/dev/null || :
  sudo systemctl disable --now systemd-networkd-wait-online.service &>/dev/null || :

  echo "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf >/dev/null
  
  # Preload & Pacman config
  [[ -f /etc/preload.conf ]] && sudo sed -i 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf
  [[ -f /etc/pacman.conf ]] && sudo sed -i -e s'/\#LogFile.*/LogFile = /'g /etc/pacman.conf

  sudo timedatectl set-timezone Europe/Berlin &>/dev/null || :

  # Documentation cleanup
  msg "Cleaning documentation"
  sudo find /usr/share/doc/ -depth -type f ! -name copyright -delete &>/dev/null || :
  sudo find /usr/share/doc/ -type f \( -name '*.gz' -o -name '*.pdf' -o -name '*.tex' \) -delete &>/dev/null || :
  sudo find /usr/share/doc/ -depth -type d -empty -delete &>/dev/null || :
  # Clean non-en_GB locales
  sudo find /usr/share/X11/locale -mindepth 1 -maxdepth 1 ! -name 'en_GB' -type d -exec rm -rf {} + 2>/dev/null || :
  sudo find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en_GB' -type d -exec rm -rf {} + 2>/dev/null || :
  sudo rm -rf /usr/share/groff /usr/share/info /usr/share/lintian /usr/share/linda /usr/share/man /var/cache/man &>/dev/null || :
  if ((aur)); then
     paru -Rcc --noconfirm man-pages &>/dev/null || :
  else
     sudo pacman -Rcc --noconfirm man-pages &>/dev/null || :
  fi

  # Flatpak fixup
  if has flatpak; then
    msg "Flush flatpak database"
    sudo flatpak uninstall --unused --delete-data -y &>/dev/null || :
    sudo flatpak repair &>/dev/null || :
  fi

  # Fonts & Icons
  msg "Optimize fonts & icons"
  if has woff2_compress; then
    find /usr/share/fonts/{opentype,truetype} -name '*ttf' -exec woff2_compress {} \; &>/dev/null || :
  fi
  sudo fc-cache -rfv &>/dev/null || :
  sudo gtk-update-icon-cache -f /usr/share/icons/* &>/dev/null || :

  # Logs & Crash handling
  msg "Clean logs & disable crashes"
  sudo rm -rf /var/crash/*
  sudo journalctl --rotate --vacuum-time=0.1 &>/dev/null || :
  
  [[ -f /etc/systemd/journald.conf ]] && sudo sed -i -e 's/^#ForwardTo\(Syslog\|KMsg\|Console\|Wall\)=.*/ForwardTo\1=no/' -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
  [[ -f /etc/logrotate.conf ]] && sudo sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
  
  echo "kernel.core_pattern=/dev/null" | sudo tee /etc/sysctl.d/50-coredump.conf >/dev/null
  sudo sed -i -e 's/^#\(DumpCore\|CrashShell\)=.*/\1=no/' /etc/systemd/{system,user}.conf 2>/dev/null || :

  # Modprobe tweaks
  [[ -f /etc/modprobe.d/disable-usb-autosuspend.conf ]] || echo "options usbcore autosuspend=-1" | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf >/dev/null
  sudo update-ca-trust &>/dev/null || :
  echo "options processor ignore_ppc=1" | sudo tee /etc/modprobe.d/ignore_ppc.conf >/dev/null
  echo "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null

  cat <<EOF | sudo tee /etc/modprobe.d/misc.conf >/dev/null
options vfio_pci disable_vga=1
options cec debug=0
options kvm mmu_audit=0 ignore_msrs=1 report_ignored_msrs=0 kvmclock_periodic_sync=1
options nfs enable_ino64=1
options libata allow_tpm=0 ignore_hpa=0
options libahci ignore_sss=1 skip_host_reset=1
options uhci-hcd debug=0
options usbcore usbfs_snoop=0 autosuspend=10
EOF
  printf '%s\n' bfq ntsync tcp_bbr zram | sudo tee /etc/modprobe.d/modules.conf >/dev/null

  # VSCode Privacy
  msg "Configure VSCode privacy"
  _vscode_json_set(){
    local prop=$1 val=$2
    has python3 || return 0
    python3 -c "from pathlib import Path;import os,json;p='$prop';t=json.loads('$val');h=f'/home/{os.getenv(\"SUDO_USER\",os.getenv(\"USER\"))}';[Path(f).write_text(json.dumps({**json.loads(c if(c:=Path(f).read_text()).strip()else'{}'),p:t},indent=2))for f in[f'{h}/.config/{e}/User/settings.json'for e in['Code','VSCodium','Void']]+[f'{h}/.var/app/com.visualstudio.code/config/Code/User/settings.json']if Path(f).is_file()and(c:=Path(f).read_text())and p not in(o:=json.loads(c if c.strip()else'{}'))or o.get(p)!=t]" 2>/dev/null || :
  }
  
  for setting in \
    'telemetry.telemetryLevel:"off"' \
    'telemetry.enableTelemetry:false' \
    'telemetry.enableCrashReporter:false' \
    'workbench.enableExperiments:false' \
    'update.mode:"none"' \
    'update.channel:"none"' \
    'update.showReleaseNotes:false' \
    'npm.fetchOnlinePackageInfo:false' \
    'git.autofetch:false' \
    'workbench.settings.enableNaturalLanguageSearch:false' \
    'typescript.disableAutomaticTypeAcquisition:false' \
    'workbench.experimental.editSessions.enabled:false' \
    'workbench.experimental.editSessions.autoStore:false' \
    'workbench.editSessions.autoResume:false' \
    'workbench.editSessions.continueOn:false' \
    'extensions.autoUpdate:false' \
    'extensions.autoCheckUpdates:false' \
    'extensions.showRecommendationsOnlyOnDemand:true'; do
    IFS=: read -r key val <<< "$setting"
    _vscode_json_set "$key" "$val"
  done
}

#══════════════════════════════════════════════════════════════
#  CLEANUP
#══════════════════════════════════════════════════════════════
cleanup(){
  msg "Cleaning up"
  local orphans
  orphans=$(pacman -Qdtq 2>/dev/null) && sudo pacman -Rns --noconfirm "$orphans" 2>/dev/null || :
  ((aur)) && paru -Scc --noconfirm 2>/dev/null || sudo pacman -Scc --noconfirm 2>/dev/null || :
  sudo journalctl --rotate -q 2>/dev/null || :
  sudo journalctl --vacuum-size=50M -q 2>/dev/null || :
  sudo fstrim -av 2>/dev/null || :
}

#══════════════════════════════════════════════════════════════
#  MAIN EXECUTION
#══════════════════════════════════════════════════════════════
main(){
  setup_repositories
  init_system
  install_packages
  setup_flatpak
  setup_rust
  setup_tools
  setup_shells
  wait # Shell background jobs
  enable_services
  maintenance
  auto_setup_tweaks
  cleanup

  msg "Setup complete! Restart shell."
  [[ -f "$HOME/failed_pkgs.txt" ]] && warn "Check ~/failed_pkgs.txt for failures"
}

main "$@"
