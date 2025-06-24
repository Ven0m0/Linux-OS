#!/bin/bash
set -euo pipefail

export LC_ALL=C
export LANG=C
sudo -v

# Set performance profiles
powerprofilesctl set performance
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Start playit in a new Konsole window and detach immediately
# konsole --noclose -e playit &
#ghostty -e playit &
#sleep 2

# Now start the Minecraft server in the terminal
#ghostty -e ./start.sh

ghostty -e bash -c 'playit & ./start.sh; kill %1'