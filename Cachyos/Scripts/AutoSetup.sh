#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'
has() { command -v "$1" &> /dev/null; }
log() { printf '%b\n' "$*"; }
msg() { printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
warn() { printf '%b%s%b\n' "$YLW" "$*" "$DEF"; }
die() {
  printf '%b%s%b\n' "$RED" "$*" "$DEF" >&2
  exit "${2:-1}"
}

ROOT_DEV=$(findmnt -n -o SOURCE /)
FSTYPE=$(findmnt -n -o FSTYPE /)
[[ $FSTYPE == "ext4" ]] && {
  log "Applying ext4 fast_commit on $ROOT_DEV"
  sudo tune2fs -O fast_commit "$ROOT_DEV"
} || log "Skipping tune2fs (filesystem: $FSTYPE)"

log "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"
locale -a | grep -q '^en_US\.utf8$' && export LANG='en_US.UTF-8' LANGUAGE='en_US' || export LANG='C.UTF-8'

log "Debloat and fixup"
sudo pacman -Rns cachyos-v4-mirrorlist --noconfirm || :
sudo pacman -Rns cachy-browser --noconfirm || :

log "install basher from https://github.com/basherpm/basher"
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

# https://github.com/YurinDoctrine/arch-linux-base-setup
log "Optimize writes to the disk"
for svc in journald coredump; do
  file=/etc/systemd/${svc}.conf
  # always ensure Storage=none
  kvs=(Storage=none)
  # only for journald: also Seal=no and Audit=no
  [[ $svc == journald ]] && kvs+=(Seal=no Audit=no)
  for kv in "${kvs[@]}"; do
    if grep -qE "^#*${kv%%=*}=" "$file"; then
      sudo sed -i -E "s|^#*${kv%%=*}=.*|$kv|" "$file"
    else
      log "$kv" | sudo tee -a "$file" > /dev/null
    fi
  done
done

log "Disable bluetooth autostart"
sudo sed -i -e 's/AutoEnable.*/AutoEnable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/FastConnectable.*/FastConnectable = false/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' /etc/bluetooth/main.conf
sudo sed -i -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' /etc/bluetooth/main.conf
log "Reduce systemd timeout"
sudo sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
sudo sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf
log "Set zram"
sudo sed -i -e 's/#ALGO.*/ALGO=lz4/g' /etc/default/zramswap
sudo sed -i -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap

log "Flush bluetooth"
sudo rm -rfd /var/lib/bluetooth/*

log "Disable plymouth"
sudo systemctl mask plymouth-{read-write,start,quit,quit-wait}.service &> /dev/null

log "Disable file indexer"
sudo balooctl6 suspend
sudo balooctl6 disable && sudo balooctl6 purge
sudo systemctl disable --now plasma-baloorunner
for dir in "$HOME" "$HOME"/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

log "Enable write cache"
log "write back" | sudo tee /sys/block/*/queue/write_cache

log "Disable logging services"
sudo systemctl mask systemd-update-utmp{,-runlevel,-shutdown}.service systemd-journal-{flush,catalog-update}.service systemd-journald-{dev-log,audit}.socket &> /dev/null
log "Disable unnecessary services"
sudo systemctl disable --global speech-dispatcher smartmontools systemd-rfkill.{service,socket} &> /dev/null
sudo systemctl disable speech-dispatcher smartmontools systemd-rfkill.{service,socket} &> /dev/null
log "Enable dbus-broker"
sudo systemctl enable --global dbus-broker.service &> /dev/null
sudo systemctl enable dbus-broker.service &> /dev/null
log "Disable wait online & GPU polling"
echo -e "[connectivity]\nenabled=false" | sudo tee /etc/NetworkManager/conf.d/20-connectivity.conf &> /dev/null
sudo systemctl mask NetworkManager-wait-online.service &> /dev/null
echo "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf &> /dev/null
sudo sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf -e s'/\#LogFile.*/LogFile = /'g /etc/pacman.conf

sudo timedatectl set-timezone Europe/Berlin
log "Clean documentation"
sudo find /usr/share/doc/ -depth -type f ! -name copyright -delete || :
sudo find /usr/share/doc/ -type f \( -name '*.gz' -o -name '*.pdf' -o -name '*.tex' \) -delete || :
sudo find /usr/share/doc/ -depth -type d -empty -delete || :
sudo rm -rf /usr/share/{groff,info,lintian,linda,man,X11/locale/!(en_GB),locale/!(en_GB)}/* /var/cache/man/* || :
yay -Rcc --noconfirm man-pages || :

log "Flush flatpak database"
sudo flatpak uninstall --unused --delete-data -y
sudo flatpak repair

log "Optimize fonts & icons"
woff2_compress /usr/share/fonts/{opentype,truetype}/*/*ttf || :
fc-cache -rfv
gtk-update-icon-cache || :

log "Clean logs & disable crashes"
sudo rm -rf /var/crash/*
sudo journalctl --rotate --vacuum-time=0.1
sudo sed -i -e 's/^#ForwardTo\(Syslog\|KMsg\|Console\|Wall\)=.*/ForwardTo\1=no/' -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
sudo sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
echo "kernel.core_pattern=/dev/null" | sudo tee /etc/sysctl.d/50-coredump.conf &> /dev/null
sudo sed -i -e 's/^#\(DumpCore\|CrashShell\)=.*/\1=no/' /etc/systemd/{system,user}.conf

sudo systemctl disable --now systemd-networkd-wait-online.service &> /dev/null
sudo systemctl mask systemd-networkd-wait-online.service &> /dev/null
[[ -f /etc/modprobe.d/disable-usb-autosuspend.conf ]] || echo "options usbcore autosuspend=-1" | sudo tee /etc/modprobe.d/disable-usb-autosuspend.conf &> /dev/null
sudo update-ca-trust
echo "options processor ignore_ppc=1" | sudo tee /etc/modprobe.d/ignore_ppc.conf &> /dev/null
echo "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" | sudo tee /etc/modprobe.d/nvidia.conf &> /dev/null

cat << EOF | sudo tee /etc/modprobe.d/misc.conf &> /dev/null
options vfio_pci disable_vga=1
options cec debug=0
options kvm mmu_audit=0 ignore_msrs=1 report_ignored_msrs=0 kvmclock_periodic_sync=1
options nfs enable_ino64=1
options libata allow_tpm=0 ignore_hpa=0
options libahci ignore_sss=1 skip_host_reset=1
options uhci-hcd debug=0
options usbcore usbfs_snoop=0 autosuspend=10
EOF
printf '%s\n' bfq ntsync tcp_bbr zram | sudo tee /etc/modprobe.d/modules.conf &> /dev/null

vscode_json_set() {
  local prop=$1 val=$2
  has python3 || return 0
  python3 -c "from pathlib import Path;import os,json;p='$prop';t=json.loads('$val');h=f'/home/{os.getenv(\"SUDO_USER\",os.getenv(\"USER\"))}';[Path(f).write_text(json.dumps({**json.loads(c if(c:=Path(f).read_text()).strip()else'{}'),p:t},indent=2))for f in[f'{h}/.config/{e}/User/settings.json'for e in['Code','VSCodium','Void']]+[f'{h}/.var/app/com.visualstudio.code/config/Code/User/settings.json']if Path(f).is_file()and(c:=Path(f).read_text())and p not in(o:=json.loads(c if c.strip()else'{}'))or o.get(p)!=t]" 2> /dev/null || :
}
log "Configure VSCode privacy"
for setting in 'telemetry.telemetryLevel:"off"' 'telemetry.enableTelemetry:false' 'telemetry.enableCrashReporter:false' 'workbench.enableExperiments:false' 'update.mode:"none"' 'update.channel:"none"' 'update.showReleaseNotes:false' 'npm.fetchOnlinePackageInfo:false' 'git.autofetch:false' 'workbench.settings.enableNaturalLanguageSearch:false' 'typescript.disableAutomaticTypeAcquisition:false' 'workbench.experimental.editSessions.enabled:false' 'workbench.experimental.editSessions.autoStore:false' 'workbench.editSessions.autoResume:false' 'workbench.editSessions.continueOn:false' 'extensions.autoUpdate:false' 'extensions.autoCheckUpdates:false' 'extensions.showRecommendationsOnlyOnDemand:true'; do
  IFS=: read -r key val <<< "$setting"
  vscode_json_set "$key" "$val"
done
