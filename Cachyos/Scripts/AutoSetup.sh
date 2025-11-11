#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Initialize privilege tool
PRIV_CMD=$(init_priv)

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ $FSTYPE == "ext4" ]]; then
  log "Root filesystem is ext4 on $ROOT_DEV"
  run_priv tune2fs -O fast_commit "$ROOT_DEV"
else
  log "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

run_priv balooctl6 disable && run_priv balooctl6 purge

log "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

# Locale
locale -a | grep -q '^en_US\.utf8$' && { export LANG='en_US.UTF-8' LANGUAGE='en_US'; } || export LANG='C.UTF-8'

run_priv curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/etc/sysctl.d/99-tweak-settings.conf -o /etc/sysctl.d/99-tweak-settings.conf

log "Debloat and fixup"
run_priv pacman -Rns cachyos-v4-mirrorlist --noconfirm || :
run_priv pacman -Rns cachy-browser --noconfirm || :

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
      log "$kv" | run_priv tee -a "$file" >/dev/null
    fi
  done
done

log "Disable bluetooth autostart"
run_priv sed -i -e 's/AutoEnable.*/AutoEnable = false/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/FastConnectable.*/FastConnectable = false/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' /etc/bluetooth/main.conf

log "Reduce systemd timeout"
run_priv sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
run_priv sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf

## Set zram
run_priv sed -i -e 's/#ALGO.*/ALGO=lz4/g' /etc/default/zramswap
run_priv sed -i -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap

## Flush bluetooth
run_priv rm -rfd /var/lib/bluetooth/*

log "Disable plymouth"
run_priv systemctl mask plymouth-read-write.service >/dev/null 2>&1
run_priv systemctl mask plymouth-start.service >/dev/null 2>&1
run_priv systemctl mask plymouth-quit.service >/dev/null 2>&1
run_priv systemctl mask plymouth-quit-wait.service >/dev/null 2>&1

## Disable file indexer
balooctl suspend
balooctl disable
balooctl purge
run_priv systemctl disable plasma-baloorunner
for dir in "$HOME" "$HOME"/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

log "Enable write cache"
log "write back" | run_priv tee /sys/block/*/queue/write_cache

log "Disable logging services"
run_priv systemctl mask systemd-update-utmp.service >/dev/null 2>&1
run_priv systemctl mask systemd-update-utmp-runlevel.service >/dev/null 2>&1
run_priv systemctl mask systemd-update-utmp-shutdown.service >/dev/null 2>&1
run_priv systemctl mask systemd-journal-flush.service >/dev/null 2>&1
run_priv systemctl mask systemd-journal-catalog-update.service >/dev/null 2>&1
run_priv systemctl mask systemd-journald-dev-log.socket >/dev/null 2>&1
run_priv systemctl mask systemd-journald-audit.socket >/dev/null 2>&1
log "Disable speech-dispatcher"
run_priv systemctl disable speech-dispatcher
run_priv systemctl --global disable speech-dispatcher
log "Disable smartmontools"
run_priv systemctl disable smartmontools
run_priv systemctl --global disable smartmontools
log "Disable systemd radio service/socket"
run_priv systemctl disable systemd-rfkill.service
run_priv systemctl --global disable systemd-rfkill.service
run_priv systemctl disable systemd-rfkill.socket
run_priv systemctl --global disable systemd-rfkill.socket
log "Enable dbus-broker"
run_priv systemctl enable dbus-broker.service
run_priv systemctl --global enable dbus-broker.service
log "Disable wait online service"
log "[connectivity]
enabled=false" | run_priv tee /etc/NetworkManager/conf.d/20-connectivity.conf
run_priv systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1

log "Disable GPU polling"
log "options drm_kms_helper poll=0" | run_priv tee /etc/modprobe.d/disable-gpu-polling.conf

## Improve preload
run_priv sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf

# Disable pacman logging.
run_priv sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

run_priv timedatectl set-timezone Europe/Berlin

# Don't reserve space man-pages, locales, licenses.
log "Remove useless companies"
find /usr/share/doc/ -depth -type f ! -name copyright -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.gz' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.pdf' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.tex' -exec sudo rm -f {} + || :
find /usr/share/doc/ -depth -type d -empty -exec sudo rmdir {} + || :
run_priv rm -rfd /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
  /usr/share/linda/* /var/cache/man/* /usr/share/man/* /usr/share/X11/locale/!\(en_GB\)
run_priv rm -rfd /usr/share/locale/!\(en_GB\)
yay -Rcc --noconfirm man-pages

log "Flush flatpak database"
run_priv flatpak uninstall --unused --delete-data -y
run_priv flatpak repair

log "Compress fonts"
woff2_compress /usr/share/fonts/opentype/*/*ttf
woff2_compress /usr/share/fonts/truetype/*/*ttf
## Optimize font cache
fc-cache -rfv
## Optimize icon cache
gtk-update-icon-cache

log "Clean crash log"
run_priv rm -rfd /var/crash/*
log "Clean archived journal"
run_priv journalctl --rotate --vacuum-time=0.1
run_priv sed -i -e 's/^#ForwardToSyslog=yes/ForwardToSyslog=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToKMsg=yes/ForwardToKMsg=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToConsole=yes/ForwardToConsole=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToWall=yes/ForwardToWall=no/' /etc/systemd/journald.conf
log "Compress log files"
run_priv sed -i -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
log "kernel.core_pattern=/dev/null" | run_priv tee /etc/sysctl.d/50-coredump.conf

#--Disable crashes
run_priv sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/system.conf
run_priv sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/system.conf
run_priv sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/user.conf
run_priv sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/user.conf

#--Update CA
run_priv update-ca-trust

doas sh -c 'touch /etc/modprobe.d/ignore_ppc.conf; log "options processor ignore_ppc=1" >/etc/modprobe.d/ignore_ppc.conf'

doas sh -c 'touch /etc/modprobe.d/nvidia.conf; log "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" >/etc/modprobe.d/nvidia.conf'

log "options vfio_pci disable_vga=1
                   options cec debug=0
                   options kvm mmu_audit=0
                   options kvm ignore_msrs=1
                   options kvm report_ignored_msrs=0
                   options kvm kvmclock_periodic_sync=1
                   options nfs enable_ino64=1
                   options libata allow_tpm=0
                   options libata ignore_hpa=0
                   options libahci ignore_sss=1
                   options libahci skip_host_reset=1
                   options uhci-hcd debug=0
                   options usbcore usbfs_snoop=0
                   options usbcore autosuspend=10" | doas tee /etc/modprobe.d/misc.conf

log "bfq
      ntsync
      tcp_bbr
      zram" | doas tee /etc/modprobe.d/modules.conf


vscode_json_set(){
  local prop=$1 val=$2
  has python3 || { log "Skipping VSCode setting (no python3): $prop"; return; }
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name='$prop'
target=json.loads('$val')
home_dir=f'/home/{os.getenv("SUDO_USER",os.getenv("USER"))}'
settings_files=[
  f'{home_dir}/.config/Code/User/settings.json',
  f'{home_dir}/.config/VSCodium/User/settings.json',
  f'{home_dir}/.config/Void/User/settings.json',
  f'{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json'
]
for sf in settings_files:
  file=Path(sf)
  if not file.is_file(): continue
  content=file.read_text()
  if not content.strip(): content='{}'
  try: obj=json.loads(content)
  except json.JSONDecodeError: continue
  if property_name in obj and obj[property_name]==target: continue
  obj[property_name]=target
  file.write_text(json.dumps(obj,indent=2))
EOF
}
  # VSCode privacy settings
  vscode_json_set 'telemetry.telemetryLevel' '"off"'
  vscode_json_set 'telemetry.enableTelemetry' 'false'
  vscode_json_set 'telemetry.enableCrashReporter' 'false'
  vscode_json_set 'workbench.enableExperiments' 'false'
  vscode_json_set 'update.mode' '"none"'
  vscode_json_set 'update.channel' '"none"'
  vscode_json_set 'update.showReleaseNotes' 'false'
  vscode_json_set 'npm.fetchOnlinePackageInfo' 'false'
  vscode_json_set 'git.autofetch' 'false'
  vscode_json_set 'workbench.settings.enableNaturalLanguageSearch' 'false'
  vscode_json_set 'typescript.disableAutomaticTypeAcquisition' 'false'
  vscode_json_set 'workbench.experimental.editSessions.enabled' 'false'
  vscode_json_set 'workbench.experimental.editSessions.autoStore' 'false'
  vscode_json_set 'workbench.editSessions.autoResume' 'false'
  vscode_json_set 'workbench.editSessions.continueOn' 'false'
  vscode_json_set 'extensions.autoUpdate' 'false'
  vscode_json_set 'extensions.autoCheckUpdates' 'false'
  vscode_json_set 'extensions.showRecommendationsOnlyOnDemand' 'true'
