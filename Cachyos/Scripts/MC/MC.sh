#!/bin/bash
set -euo pipefail

export LC_ALL=C
export LANG=C

sudo -v

powerprofilesctl set performance
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Detect if running inside ghostty terminal
if [[ "$TERM" == "ghostty" ]]; then
  # Inside ghostty terminal:
  # 1) Launch playit in new ghostty terminal
  # 2) Run start.sh here (current ghostty terminal)

  ghostty -e bash -c '
    playit &
    PLAYIT_PID=$!
    trap "kill $PLAYIT_PID 2>/dev/null || true" EXIT INT TERM
    wait
  ' &

  # Sleep a bit to let playit start
  read -rt 1 || true

  # Run start.sh in current terminal, foreground
  ./start.sh

else
  # Not inside ghostty:
  # Launch both playit and start.sh together in new ghostty terminal
  ghostty -e bash -c '
    playit &
    PLAYIT_PID=$!
    trap "kill $PLAYIT_PID 2>/dev/null || true" EXIT INT TERM
    read -rt 1 || true
    ./start.sh
  '
fi
