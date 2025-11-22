#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
# shellcheck shell=bash

# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Enable IP forwarding for IPv4 and IPv6
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
sudo sysctl -w net.ipv6.conf.default.forwarding=1

# Make changes persistent
sudo tee /etc/sysctl.d/99-ip-forward.conf >/dev/null <<'EOF'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF

echo "IP forwarding enabled and persisted to /etc/sysctl.d/99-ip-forward.conf"
