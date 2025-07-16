#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

export LC_ALL=C LANG=C
# export LC_ALL=C LANG=C.UTF-8

# Cache commands
hash -r
hash sudo
hash grep rg fd find awk
hash cp rm mv tee
hash pacman paru cargo git
hash clang rustc make
hash ghostty konsole rio alacritty
hash java
sudo -v

echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sudo powerprofilesctl set performance
sudo cpupower frequency-set -g performance

echo 1024 | sudo tee /sys/block/sda/queue/read_ahead_kb >/dev/null
echo 1024 | sudo tee /sys/block/sda/queue/nr_requests >/dev/null
echo 0 | sudo tee /sys/block/sda/queue/add_random >/dev/null
