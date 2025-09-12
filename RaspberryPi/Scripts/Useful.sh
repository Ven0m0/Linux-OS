#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"


Get_IPs() {
    # Try ip command first (more reliable)
    if command -v ip >/dev/null 2>&1; then
        # Get all IPv4 addresses, exclude loopback (127.0.0.0/8) and docker interfaces
        ip -4 addr show | grep -v "inet 127\." | grep -v "docker" | grep -v "br-" | grep -v "veth" | grep "inet" | awk '{print $2}' | cut -d/ -f1
    # Fall back to ifconfig if ip command is not available
    elif command -v ifconfig >/dev/null 2>&1; then
        # Get all IPv4 addresses, exclude loopback (127.0.0.0/8) and docker interfaces
        ifconfig | grep -v "inet 127\." | grep -v "docker" | grep -v "br-" | grep -v "veth" | grep "inet" | awk '{print $2}' | cut -d: -f2
    # Last resort, try hostname -I but filter out loopback addresses
    else
        hostname -I | tr ' ' '\n' | grep -v "^127\." | head -n 1
    fi
}

# Get the first valid LAN IP address
lan_ip=$(Get_IPs | head -n 1)
