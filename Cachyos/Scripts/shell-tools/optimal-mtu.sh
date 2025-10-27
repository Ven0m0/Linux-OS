#!/bin/bash

# This script finds the optimal MTU for a network interface and sets it.
# It uses a binary search algorithm to efficiently find the best MTU value.

find_best_mtu() {
  local server_ip=8.8.8.8 # Google DNS server
  local low=1200          # Lower bound MTU
  local high=1500         # Standard MTU
  local optimal=0

  echo "[MTU LOG] Starting MTU search for server: $server_ip"

  # Check if the server is reachable
  if ! ping -c 1 -W 1 "$server_ip" &>/dev/null; then
    echo "[MTU LOG] ERROR: Server $server_ip unreachable."
    return 1
  fi

  # Verify that the minimum MTU works
  if ! ping -M do -s $((low - 28)) -c 1 "$server_ip" &>/dev/null; then
    echo "[MTU LOG] ERROR: Minimum MTU of $low bytes not viable."
    return 1
  fi

  optimal=$low
  # Use binary search to find the highest MTU that works
  while [[ $low -le $high ]]; do
    local mid=$(((low + high) / 2))
    if ping -M do -s $((mid - 28)) -c 1 "$server_ip" &>/dev/null; then
      optimal=$mid
      low=$((mid + 1))
    else
      high=$((mid - 1))
    fi
  done

  echo "[MTU LOG] Optimal MTU found: ${optimal} bytes"

  # Ask user if they want to set the current MTU to the found value
  read -p "[MTU LOG] Do you want to set the optimal MTU on a network interface? (Y/n): " set_mtu_choice
  if [[ -z $set_mtu_choice || $set_mtu_choice =~ ^[Yy] ]]; then
    read -p "[MTU LOG] Enter the network interface name: " iface
    if [[ -z $iface ]]; then
      echo "[MTU LOG] ERROR: No interface provided."
      return 1
    fi

    # Attempt to set the MTU using the ip command
    if ip link set dev "$iface" mtu "$optimal"; then
      echo "[MTU LOG] MTU set to ${optimal} bytes on interface $iface"
    else
      echo "[MTU LOG] ERROR: Failed to set MTU on interface $iface"
      return 1
    fi
  else
    echo "[MTU LOG] MTU setting skipped by user."
  fi

  return 0
}

# Run the function
find_best_mtu
