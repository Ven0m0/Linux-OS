#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C

echo "Running DietPi housekeeping tasks..."

# Run optimal MTU configuration
if command -v dietpi-optimal_mtu &>/dev/null>/dev/null; then
  echo "Running dietpi-optimal_mtu..."
  dietpi-optimal_mtu
elif [[ -x /boot/dietpi/func/dietpi-optimal_mtu ]]; then
  echo "Running /boot/dietpi/func/dietpi-optimal_mtu..."
  /boot/dietpi/func/dietpi-optimal_mtu
fi

# Run DietPi cleaner
if command -v dietpi-cleaner &>/dev/null>/dev/null; then
  echo "Running dietpi-cleaner..."
  dietpi-cleaner
elif [[ -x /boot/dietpi/dietpi-cleaner ]]; then
  echo "Running /boot/dietpi/dietpi-cleaner..."
  /boot/dietpi/dietpi-cleaner
fi

echo "Housekeeping complete!"
