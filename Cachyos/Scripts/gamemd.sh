#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'
has() { command -v -- "$1" &> /dev/null; }

echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &> /dev/null
echo within_size | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled &> /dev/null
echo 1 | sudo tee /sys/kernel/mm/ksm/use_zero_pages &> /dev/null
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo &> /dev/null
echo 1 | sudo tee /proc/sys/vm/page_lock_unfairness &> /dev/null
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/use_zero_page &> /dev/null
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/shrink_underused &> /dev/null
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler &> /dev/null
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &> /dev/null
sudo powerprofilesctl set performance &> /dev/null
sudo cpupower frequency-set -g performance &> /dev/null
echo 512 | sudo tee /sys/block/nvme0n1/queue/nr_requests &> /dev/null
echo 1024 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb &> /dev/null
echo 0 | sudo tee /sys/block/sda/queue/add_random &> /dev/null
echo performance | sudo tee /sys/module/pcie_aspm/parameters/policy &> /dev/null

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
# Enable HDD write cache:
# hdparm -W 1 /dev/sdX
# Disables aggressive power-saving, but keeps APM enabled
# hdparm -B 254
# Completely disables APM
# hdparm -B 255
if has gamemoderun; then
  gamemoderun
fi
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches
