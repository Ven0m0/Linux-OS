#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# DESCRIPTION: Raspberry Pi system optimization suite
sync
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Helpers
has() { command -v -- "$1" &> /dev/null; }
log() { printf '%b\n' "${GRN}▶${DEF} $*"; }
warn() { printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err() { printf '%b\n' "${RED}✗${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}
# Config
declare -A cfg=([dry_run]=0 [interactive]=1 [aggressive]=0 [disk_before]=0 [disk_after]=0)
run() { ((cfg[dry_run])) && log "[DRY] $*" || "$@"; }
# Disk usage tracking
track_disk() {
  local label="$1" usage
  usage=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
  log "${BLD}${label}:${DEF} ${usage}"
  [[ $label == "Before" ]] && cfg[disk_before]=$usage || cfg[disk_after]=$usage
}
# Interactive prompt
ask() {
  ((cfg[interactive] == 0)) && return 0
  local prompt="$1" default="${2:-n}" reply
  read -rp "${LBLU}?${DEF} ${prompt} [${default}] " reply
  reply=${reply:-$default}
  [[ $reply =~ ^[Yy] ]]
}
usage() {
  cat << 'EOF'
pi-minify.sh - Raspberry Pi system minimization, cleanup & privacy hardening
Usage: pi-minify.sh [OPTIONS]
Options:
  -y, --yes          Non-interactive mode (assumes yes)
  -d, --dry-run      Show actions without executing
  -a, --aggressive   Enable aggressive cleanup (X11, dev pkgs, kernels)
  -h, --help         Show this help
Operations:
  • dpkg nodoc configuration + doc/man/locale purge
  • APT cache cleanup + orphan removal
  • Old kernel purge (keeps current)
  • Privacy hardening (popcon, reportbug, crash dumps, logs)
  • Clean privacy data (screenshots, recently-used, zeitgeist)
  • Disable Python history permanently
  • Optional: SWAP→ZRAM migration
  • Optional: X11/dev package removal
  • Log/cache/history cleanup
  • fstab optimization (noatime, nodiratime)
  • systemd timeout tuning
CAUTION: Aggressive mode removes X11, -dev packages, and non-current kernels
EOF
}
parse_args() {
  while (($#)); do
    case "$1" in
      -y | --yes) cfg[interactive]=0 ;;
      -d | --dry-run) cfg[dry_run]=1 ;;
      -a | --aggressive) cfg[aggressive]=1 ;;
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
# dpkg & Documentation
configure_dpkg_nodoc() {
  log "Configuring dpkg to exclude docs/man/locales"
  sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc > /dev/null << 'EOF'
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
purge_docs() {
  log "Purging documentation, man pages, locales (keep en_US)"
  run find /usr/share/doc/ -depth -type f ! -name copyright -delete 2> /dev/null || :
  run find /usr/share/doc/ -name '*.gz' -o -name '*.pdf' -o -name '*.tex' -delete 2> /dev/null || :
  run find /usr/share/doc/ -type d -empty -delete 2> /dev/null || :
  sudo rm -rf /usr/share/{groff,info,lintian,linda,man}/* /var/cache/man/* 2> /dev/null || :
  local keep_locale=en_US
  sudo bash -c "cd /usr/share/locale && ls | grep -v ${keep_locale} | xargs rm -rf" 2> /dev/null || :
  sudo bash -c "cd /usr/share/X11/locale && ls | grep -v ${keep_locale} | xargs rm -rf" 2> /dev/null || :
}
# Package Cleanup
purge_packages() {
  log "Removing doc packages, localepurge install"
  has localepurge || sudo apt-get install -y localepurge
  run localepurge
  local doc_pkgs
  mapfile -t doc_pkgs < <(dpkg --list | awk '/-doc$/ {print $2}')
  ((${#doc_pkgs[@]} > 0)) && sudo apt-get purge -y "${doc_pkgs[@]}" || :
  sudo apt-get purge -y '*texlive*' 2> /dev/null || :
  local current_kernel
  current_kernel=$(uname -r)
  local old_kernels
  mapfile -t old_kernels < <(dpkg --list | awk -v ck="$current_kernel" '$2 ~ /^linux-image-.*-generic$/ && $2 != ck {print $2}')
  ((${#old_kernels[@]} > 0)) && {
    log "Purging old kernels (keeping ${current_kernel})"
    sudo apt-get purge -y "${old_kernels[@]}"
  }
  local orphaned
  mapfile -t orphaned < <(dpkg -l | awk '/^rc/ {print $2}')
  ((${#orphaned[@]} > 0)) && sudo apt-get purge -y "${orphaned[@]}" || :
}
purge_aggressive() {
  ((cfg[aggressive] == 0)) && return 0
  warn "Aggressive mode: removing X11, dev packages, extras"
  sudo apt-get purge -y libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6 2> /dev/null || :
  sudo apt-get purge -y popularity-contest installation-report wireless-tools wpasupplicant libraspberrypi-doc snapd 'cups*' 2> /dev/null || :
}
cleanup_apt() {
  log "APT cleanup: cache, orphans, deborphan"
  has deborphan || sudo apt-get install -y deborphan
  sudo apt-get autoremove --purge -y
  sudo apt-get autoclean -y
  sudo apt-get clean -y
  local orphans
  while mapfile -t orphans < <(deborphan) && ((${#orphans[@]} > 0)); do sudo apt-get purge -y "${orphans[@]}"; done
}
debloat() {
  systemctl disable --now systemd-binfmt proc-sys-fs-binfmt_misc.automount sys-fs-fuse-connections.mount sys-kernel-config.mount
  systemctl mask systemd-binfmt proc-sys-fs-binfmt_misc.automount sys-fs-fuse-connections.mount sys-kernel-config.mount
}
# Cache & Temp Cleanup
clean_caches() {
  log "Cleaning caches, temp files, history"
  sudo rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/* 2> /dev/null || :
  run rm -rf ~/.cache/* ~/.thumbnails/* ~/.cache/thumbnails/* 2> /dev/null || :
  sudo rm -rf /root/.cache/* 2> /dev/null || :
  run rm -rf ~/.local/share/Trash/* 2> /dev/null || :
  sudo rm -rf /root/.local/share/Trash/* 2> /dev/null || :
  run rm -rf ~/snap/*/*/.local/share/Trash/* 2> /dev/null || :
  run rm -rf ~/.var/app/*/data/Trash/* 2> /dev/null || :
  unset HISTFILE
  run rm -f ~/.{bash,python}_history 2> /dev/null || :
  sudo rm -f /root/.{bash,python}_history 2> /dev/null || :
  history -c 2> /dev/null || :
  while IFS= read -r logfile; do sudo truncate -s 0 "$logfile" 2> /dev/null || sudo sh -c ":> \"$logfile\"" 2> /dev/null || :; done < <(find /var/log -type f)
}
# Privacy & Security Hardening
clean_crash_dumps() {
  log "Cleaning crash dumps and core dumps"
  has coredumpctl && sudo coredumpctl --quiet --no-legend clean 2> /dev/null || :
  sudo rm -rf /var/crash/* 2> /dev/null || :
  sudo rm -rf /var/lib/systemd/coredump/* 2> /dev/null || :
}
clean_system_logs() {
  log "Clearing system logs (journald)"
  sudo journalctl --vacuum-time=1s
  sudo rm -rf /run/log/journal/* 2> /dev/null || :
  sudo rm -rf /var/log/journal/* 2> /dev/null || :
}
disable_python_history() {
  log "Disabling Python history permanently"
  local history_file="$HOME/.python_history"
  [[ ! -f $history_file ]] && touch "$history_file"
  sudo chattr +i "$(realpath "$history_file")" 2> /dev/null || :
}
remove_popcon() {
  log "Removing Popularity Contest (popcon)"
  local config_file='/etc/popularity-contest.conf'
  [[ -f $config_file ]] && sudo sed -i '/PARTICIPATE/c\PARTICIPATE=no' "$config_file"
  local cronjob_path="/etc/cron.daily/popularity-contest"
  [[ -f $cronjob_path && -x $cronjob_path ]] && sudo chmod -x "$cronjob_path"
  if has apt-get; then
    local pkg='popularity-contest'
    if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$pkg" 2>&1)" && [[ $status == installed ]]; then sudo apt-get purge -y "$pkg"; fi
  fi
}
remove_reportbug() {
  log "Removing reportbug packages"
  has apt-get || return 0
  local pkgs=('reportbug' 'python3-reportbug' 'reportbug-gtk')
  local pkg
  for pkg in "${pkgs[@]}"; do
    if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$pkg" 2>&1)" && [[ $status == installed ]]; then sudo apt-get purge -y "$pkg"; fi
  done
}
clean_privacy_data() {
  log "Cleaning privacy-sensitive data"
  sudo rm -rf {/root,/home/*}/.local/share/zeitgeist 2> /dev/null || :
  run rm -rf ~/Pictures/Screenshots/* 2> /dev/null || :
  [[ -d ~/Pictures ]] && {
    find ~/Pictures -name 'Screenshot from *.png' -delete 2> /dev/null || :
    find ~/Pictures -name 'Screenshot_*' -delete 2> /dev/null || :
  }
  find ~ -name 'ksnip_*' -delete 2> /dev/null || :
  run rm -f /.recently-used.xbel 2> /dev/null || :
  run rm -f ~/.local/share/recently-used.xbel* 2> /dev/null || :
  run rm -f ~/snap/*/*/.local/share/recently-used.xbel 2> /dev/null || :
  run rm -f ~/.var/app/*/data/recently-used.xbel 2> /dev/null || :
  run rm -rf "$HOME/.config/privacy.sexy/runs"/* 2> /dev/null || :
  run rm -rf "$HOME/.config/privacy.sexy/logs"/* 2> /dev/null || :
}
# ZRAM Setup
disable_swap() {
  log "Disabling SWAP partition"
  has dphys-swapfile && {
    sudo dphys-swapfile swapoff
    sudo dphys-swapfile uninstall
    sudo update-rc.d dphys-swapfile remove
  }
  sudo swapoff -a
}
enable_zram() {
  log "Enabling ZRAM (compressed swap in RAM)"
  sudo tee /usr/local/bin/zram-init > /dev/null << 'ZRAMSCRIPT'
#!/bin/bash
set -euo pipefail
CORES=$(nproc); ZRAM_SIZE_MB=${ZRAM_SIZE_MB:-2048}
modprobe zram num_devices="${CORES}"; swapoff -a 2>/dev/null || :
MEMTOTAL=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo); SIZE=$(( (MEMTOTAL / CORES) * 1024 ))
[[ ${ZRAM_SIZE_MB} -gt 0 ]] && SIZE=$(( ZRAM_SIZE_MB * 1024 * 1024 / CORES ))
for ((CORE=0; CORE<CORES; CORE++)); do
  echo "${SIZE}"> /sys/block/zram${CORE}/disksize; mkswap /dev/zram${CORE} &>/dev/null; swapon -p 5 /dev/zram${CORE}
done
echo 1> /sys/kernel/mm/ksm/run
ZRAMSCRIPT
  sudo chmod +x /usr/local/bin/zram-init
  sudo /usr/local/bin/zram-init
  sudo tee /etc/systemd/system/zram-init.service > /dev/null << 'EOF'
[Unit]
Description=ZRAM compressed swap initialization
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/zram-init
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable zram-init.service
}
# System Tweaks
optimize_fstab() {
  log "Optimizing fstab: noatime, nodiratime"
  sudo sed -i 's/\(defaults\)/\1,noatime,nodiratime/' /etc/fstab
}
optimize_systemd() {
  log "Reducing systemd stop timeout: 90s→5s"
  sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf
}
disable_extra_ttys() {
  [[ ! -f /etc/inittab ]] && return 0
  log "Disabling extra TTYs (2-6) for RAM savings"
  sudo sed -i '/[2-6]:23:respawn:\/sbin\/getty 38400 tty[2-6]/s/^/#/' /etc/inittab
}
# Main Orchestration
main() {
  parse_args "$@"
  log "${BLD}Raspberry Pi System Minification & Privacy Hardening${DEF}"
  log "Mode: $([[ ${cfg[dry_run]} -eq 1 ]] && echo 'DRY-RUN' || echo 'LIVE')"
  log "Interactive: $([[ ${cfg[interactive]} -eq 1 ]] && echo 'YES' || echo 'NO')"
  log "Aggressive: $([[ ${cfg[aggressive]} -eq 1 ]] && echo 'YES' || echo 'NO')"
  track_disk "Before"
  configure_dpkg_nodoc
  purge_docs
  purge_packages
  cleanup_apt
  clean_caches
  debloat
  clean_crash_dumps
  clean_system_logs
  disable_python_history
  remove_popcon
  remove_reportbug
  clean_privacy_data
  [[ ${cfg[aggressive]} -eq 1 ]] && purge_aggressive
  ask "Disable SWAP and enable ZRAM?" y && {
    disable_swap
    enable_zram
  }
  ask "Optimize fstab (noatime, nodiratime)?" y && optimize_fstab
  ask "Reduce systemd stop timeout to 5s?" y && optimize_systemd
  ask "Disable extra TTYs (2-6) for RAM savings?" n && disable_extra_ttys
  track_disk "After"
  log "${GRN}✓${DEF} Minification & privacy hardening complete"
  log "Disk before: ${cfg[disk_before]}"
  log "Disk after:  ${cfg[disk_after]}"
  warn "Reboot recommended to fully apply changes"
}
main "$@"
