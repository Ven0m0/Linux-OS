#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

# Cache commands
if command -v sudo-rs &>/dev/null; then
  sudo-rs -v
else command -v sudo &>/dev/null; then
  sudo -v
fi

echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo advise | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled
echo 1 | sudo tee /proc/sys/vm/page_lock_unfairness
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sudo powerprofilesctl set performance
sudo cpupower frequency-set -g performance

echo 512 | sudo tee /sys/block/nvme0n1/queue/nr_requests
echo 1024 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb
echo 0 | sudo tee /sys/block/sda/queue/add_random >/dev/null

echo performance | sudo tee /sys/module/pcie_aspm/parameters/policy

# disable bluetooth
sudo systemctl stop bluetooth.service

# enable USB autosuspend
for usb_device in /sys/bus/usb/devices/*/power/control; do
    echo 'auto' | sudo tee "$usb_device" > /dev/null
done

# disable NMI watchdog
echo 0 | sudo tee /proc/sys/kernel/nmi_watchdog

# disable Wake-on-Timer
echo 0 | sudo tee /sys/class/rtc/rtc0/wakealarm

export USE_CCACHE=1

enable hdd write cache:
hdparm -W 1 /dev/sdX

Disables aggressive power-saving, but keeps APM enabled
hdparm -B 254

Completely disables APM
hdparm -B 255

if command -v gamemoderun;then
    gamemoderun
fi
