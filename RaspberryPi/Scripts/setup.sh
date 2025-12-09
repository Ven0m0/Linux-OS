#!/usr/bin/env bash
# DESCRIPTION: Automated Raspberry Pi system optimization and tooling setup
#              Targets: Debian/Raspbian, DietPi
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Core helpers
has() { command -v -- "$1" &>/dev/null; }
log() { printf '%b\n' "${GRN}▶${DEF} $*"; }
warn() { printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err() { printf '%b\n' "${RED}✗${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}
# Config flags
declare -A cfg=([dry_run]=0 [skip_external]=0 [minimal]=0 [quiet]=0)
run() { ((cfg[dry_run])) && log "[DRY] $*" || "$@"; }
# Safe cleanup workspace
WORKDIR=$(mktemp -d)
cleanup() {
  set +e
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}
trap cleanup EXIT
trap 'err "failed at line $LINENO"' ERR
usage() {
  cat <<'EOF'
pi-setup.sh - Raspberry Pi optimization & tooling automation
Usage: pi-setup.sh [OPTIONS]
Options:
  -d, --dry-run        Show actions without executing
  -s, --skip-external  Skip external installers (Pi-hole, PiKISS)
  -m, --minimal        Core optimizations only (no extra tooling)
  -q, --quiet          Suppress non-error output
  -h, --help           Show this help
Performs:
  • APT configuration (parallel downloads, compression, auto-upgrade)
  • dpkg nodoc configuration + cleanup
  • System optimization (I/O, power, journald, caching)
  • Modern tooling (fd, rg, bat, eza, zoxide, navi, yt-dlp)
  • Optional: Pi-hole, PiKISS, PiApps, apt-fast, deb-get, pacstall
EOF
}
parse_args() {
  while (($#)); do
    case "$1" in
      -d | --dry-run) cfg[dry_run]=1 ;;
      -s | --skip-external) cfg[skip_external]=1 ;;
      -m | --minimal) cfg[minimal]=1 ;;
      -q | --quiet)
        cfg[quiet]=1
        exec >/dev/null
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        die "invalid option: $1"
        ;;
      *) break ;;
    esac
    shift
  done
}
# APT Configuration
configure_apt() {
  log "Configuring APT for performance & reliability"
  sudo tee /etc/apt/apt.conf.d/99parallel >/dev/null <<'EOF'
APT::Acquire::Retries "5";
Acquire::Queue-Mode "access";
Acquire::Languages "none";
APT::Acquire::ForceIPv4 "true";
APT::Get::AllowUnauthenticated "false";
Acquire::CompressionTypes::Order:: "gz";
APT { Get { Assume-Yes "true"; Fix-Broken "true"; Fix-Missing "true"; List-Cleanup "true"; };};
APT::Acquire::Max-Parallel-Downloads "5";
EOF
  sudo tee /etc/apt/apt.conf.d/50-unattended-upgrades >/dev/null <<'EOF'
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
APT::Periodic::Update-Package-Lists "1";
Unattended-Upgrade::MinimalSteps "true";
EOF
  sudo tee /etc/apt/apt.conf.d/01disable-log >/dev/null <<'EOF'
Dir::Log::Terminal "";
EOF
  sudo tee /etc/apt/apt.conf.d/71debconf >/dev/null <<'EOF'
DPkg::Options {
   "--force-confdef";
};
EOF
  sudo tee /etc/dpkg/dpkg.cfg.d/force-unsafe-io >/dev/null <<'EOF'
force-unsafe-io
EOF
}
enable_ip_forwarding() {
  log "Enabling IP forwarding..."
  sudo sysctl -w net.ipv4.ip_forward=1
  sudo sysctl -w net.ipv6.conf.all.forwarding=1
  sudo sysctl -w net.ipv6.conf.default.forwarding=1
  sudo tee /etc/sysctl.d/99-ip-forward.conf >/dev/null <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF
}
# Documentation Cleanup
configure_dpkg_nodoc() {
  log "Configuring dpkg to exclude documentation"
  sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc >/dev/null <<'EOF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/help/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-include /usr/share/doc/*/copyright
EOF
}
clean_docs() {
  log "Removing existing documentation files"
  run find /usr/share/doc/ -depth -type f ! -name copyright -delete 2>/dev/null || :
  run find /usr/share/doc/ -name '*.gz' -o -name '*.pdf' -o -name '*.tex' -delete 2>/dev/null || :
  run find /usr/share/doc/ -type d -empty -delete 2>/dev/null || :
  sudo rm -rf /usr/share/{groff,info,lintian,linda,man}/* /var/cache/man/* 2>/dev/null || :
  sudo bash -c 'cd /usr/share/locale && for d in *; do [[ $d != en_GB ]] && rm -rf "$d"; done' 2>/dev/null || :
  sudo bash -c 'cd /usr/share/X11/locale && for d in *; do [[ $d != en_GB ]] && rm -rf "$d"; done' 2>/dev/null || :
  sudo apt-get remove --purge -y '*texlive*' '*-doc' 2>/dev/null || :
}
# System Optimization
optimize_system() {
  log "Applying system-level optimizations"
  sudo systemctl mask NetworkManager-wait-online.service 2>/dev/null || :
  sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf >/dev/null <<'EOF'
[connectivity]
enabled=false
EOF
  [[ -f /etc/selinux/config ]] && {
    sudo tee /etc/selinux/config >/dev/null <<'EOF'
SELINUX=disabled
SELINUXTYPE=minimum
EOF
    sudo setenforce 0 2>/dev/null || :
  }
  sudo tee /etc/modprobe.d/misc.conf >/dev/null <<'EOF'
options cec debug=0
options pstore backend=null
options snd_hda_intel power_save=1
options snd_ac97_codec power_save=1
options usbhid mousepoll=20 kbpoll=20
options usbcore autosuspend=10
EOF
  for dev in /sys/block/sd*[!0-9]/queue/iosched/fifo_batch /sys/block/{mmcblk*,nvme[0-9]*}/queue/iosched/fifo_batch; do
    [[ -f $dev ]] && sudo tee "$dev" >/dev/null <<<32 || :
  done
  local root_dev home_dev
  root_dev=$(findmnt -n -o SOURCE /)
  home_dev=$(findmnt -n -o SOURCE /home 2>/dev/null || echo "$root_dev")
  [[ -n $root_dev ]] && {
    sudo tune2fs -o journal_data_writeback "$root_dev" 2>/dev/null || :
    sudo tune2fs -O ^has_journal,fast_commit "$root_dev" 2>/dev/null || :
    sudo tune2fs -c 0 -i 0 "$root_dev" 2>/dev/null || :
    sudo tune2fs -O ^metadata_csum,^quota "$root_dev" 2>/dev/null || :
  }
  [[ -n $home_dev && $home_dev != "$root_dev" ]] && {
    sudo tune2fs -o journal_data_writeback "$home_dev" 2>/dev/null || :
    sudo tune2fs -O ^has_journal,fast_commit "$home_dev" 2>/dev/null || :
    sudo tune2fs -c 0 -i 0 "$home_dev" 2>/dev/null || :
    sudo tune2fs -O ^metadata_csum,^quota "$home_dev" 2>/dev/null || :
  }
  if ip -o link | grep -q wlan; then
    sudo tee /etc/modprobe.d/wlan.conf >/dev/null <<'EOF'
options iwlwifi power_save=1
options iwlmvm power_scheme=3
options rfkill default_state=0 master_switch_mode=0
EOF
    has ethtool && sudo ethtool -K wlan0 gro on gso on 2>/dev/null || :
  else
    has ethtool && {
      sudo ethtool -K eth0 gro off gso off 2>/dev/null || :
      sudo ethtool -C eth0 adaptive-rx on adaptive-tx on 2>/dev/null || :
    }
  fi
  sudo tee /etc/systemd/journald.conf.d/optimization.conf >/dev/null <<'EOF'
[Journal]
ForwardToSyslog=no
ForwardToKMsg=no
ForwardToConsole=no
ForwardToWall=no
Compress=yes
EOF
  sudo journalctl --rotate --vacuum-time=1s 2>/dev/null || :
  sudo tee /etc/sysctl.d/50-coredump.conf >/dev/null <<'EOF'
kernel.core_pattern=/dev/null
kernel.hung_task_timeout_secs=0
EOF
  sudo sysctl -w kernel.hung_task_timeout_secs=0 2>/dev/null || :
  has update-initramfs && sudo update-initramfs -u -k all || :
}
# SSH Configuration
configure_ssh() {
  log "Configuring SSH/Dropbear"
  [[ -f /etc/default/dropbear ]] && sudo sed -i 's/NO_START=1/NO_START=0/g' /etc/default/dropbear
  [[ -f /etc/ssh/sshd_config ]] && {
    sudo sed -i -E 's/#?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
  }
}
# Modern Tooling Installation
install_core_tools() {
  log "Installing core modern CLI tools"
  local tools=(fd-find ripgrep bat fzf zstd curl wget gpg btrfs-progs)
  sudo apt-get update
  sudo apt-get install -y "${tools[@]}"
  [[ -f /usr/bin/fdfind && ! -f "$HOME/.local/bin/fd" ]] && {
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
  }
}
install_extended_tools() {
  ((cfg[minimal])) && return 0
  log "Installing extended tooling suite"
  if ! has eza; then
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt-get update
    sudo apt-get install -y eza
  fi
  ! has zoxide && curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | run bash
}
# External Package Managers
install_package_managers() {
  ((cfg[minimal] || cfg[skip_external])) && return 0
  log "Installing alternative package managers"
  if ! has apt-fast; then
    sudo mkdir -p /etc/apt/keyrings /etc/apt/sources.list.d
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBC5934FD3DEBD4DAEA544F791E2824A7F22B44BD" \
      | sudo gpg --dearmor -o /etc/apt/keyrings/apt-fast.gpg
    echo "deb [signed-by=/etc/apt/keyrings/apt-fast.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu focal main" \
      | sudo tee /etc/apt/sources.list.d/apt-fast.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y apt-fast
  fi
  if ! has deb-get; then
    sudo apt-get install -y curl lsb-release wget
    curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo bash -s install deb-get
  fi
  if ! has eget; then
    curl -s https://zyedidia.github.io/eget.sh | run bash
    [[ -f ./eget ]] && {
      mkdir -p "$HOME/.local/bin"
      mv ./eget "$HOME/.local/bin/"
    }
  fi
  ! has pacstall && sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install)"
}
# External Installers (Pi-hole, PiKISS, PiApps)
install_external() {
  ((cfg[skip_external])) && return 0
  log "Running external installers (interactive)"
  if ! has pihole; then
    warn "Pi-hole installer is interactive - proceeding"
    curl -sSL https://install.pi-hole.net | sudo bash
  fi
  if ! has pi-apps; then
    curl -sSfL https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | run bash
    has pi-apps && run pi-apps update -y
  fi
  warn "PiKISS is fully interactive - skipping automated install"
  log "Manual install: git clone https://github.com/jmcerrejon/PiKISS.git && cd PiKISS && ./piKiss.sh"
}
# Main Execution
main() {
  parse_args "$@"
  log "${BLD}Raspberry Pi Setup & Optimization${DEF}"
  log "Mode: $([[ ${cfg[dry_run]} -eq 1 ]] && echo 'DRY-RUN' || echo 'LIVE')"
  log "Profile: $([[ ${cfg[minimal]} -eq 1 ]] && echo 'MINIMAL' || echo 'FULL')"
  configure_apt
  enable_ip_forwarding
  configure_dpkg_nodoc
  clean_docs
  optimize_system
  configure_ssh
  install_core_tools
  install_extended_tools
  install_package_managers
  install_external
  sudo apt-get autoremove -y
  sudo apt-get autoclean
  has flatpak && run flatpak uninstall --unused --delete-data -y || :
  log "${GRN}✓${DEF} Setup complete"
  warn "Reboot recommended to apply all optimizations"
}
main "$@"
