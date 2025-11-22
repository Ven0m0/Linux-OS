#!/usr/bin/env bash
set -euo pipefail
has(){ command -v -- "$1" &>/dev/null>/dev/null; }
die(){
  echo "ERROR: $*" >&2
  exit 1
}

# Reviewed NetOptix script - incorporated IPv6 support, Netplan support, and safety margin

detect_ip_version(){
  local addr=$1
  if [[ $addr =~ : ]]; then
    echo "6"
  else
    echo "4"
  fi
}

find_mtu(){
  local srv=${1:-8.8.8.8} lo=1200 hi=1500 mid opt iface
  local ipver=$(detect_ip_version "$srv")
  local overhead=28 # IPv4 default
  local ping_cmd="ping"

  if [[ $ipver == "6" ]]; then
    overhead=48 # IPv6 header + ICMP6
    ping_cmd="ping6"
    has ping6 || die "ping6 not available for IPv6 testing"
  fi

  echo "Testing MTU to $srv (IPv$ipver)..."
  $ping_cmd -c1 -W1 "$srv" &>/dev/null>/dev/null || die "Server $srv unreachable"
  $ping_cmd -M do -s$((lo - overhead)) -c1 "$srv" &>/dev/null>/dev/null || die "Min MTU $lo not viable"

  opt=$lo
  while ((lo <= hi)); do
    mid=$(((lo + hi) / 2))
    if $ping_cmd -M do -s$((mid - overhead)) -c1 "$srv" &>/dev/null>/dev/null 2>&1; then
      opt=$mid
      lo=$((mid + 1))
    else
      hi=$((mid - 1))
    fi
  done

  # Apply safety margin to avoid edge cases
  opt=$((opt - 4))
  echo "Optimal MTU: $opt bytes (with 4-byte safety margin)"

  read -rp "Set MTU on interface? (Y/n) " -n1 choice
  echo
  [[ $choice =~ ^[Nn]$ ]] && {
    echo "Skipped"
    return
  }

  mapfile -t ifaces < <(ip -br link | awk '$1!~/(lo|veth|docker)/{print $1}')
  ((${#ifaces[@]})) || die "No interfaces found"

  if ((${#ifaces[@]} == 1)); then
    iface=${ifaces[0]}
  else
    printf "%b\n" "\nAvailable interfaces:"
    for i in "${!ifaces[@]}"; do
      printf "%d) %s\n" $((i + 1)) "${ifaces[$i]}"
    done
    read -rp "Select [1-${#ifaces[@]}]: " n
    [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#ifaces[@]} ]] || die "Invalid selection"
    iface=${ifaces[$((n - 1))]}
  fi

  sudo ip link set dev "$iface" mtu "$opt" || die "Failed to set MTU on $iface"
  echo "MTU set to $opt on $iface"

  read -rp "Make persistent? (y/N) " -n1 persist
  echo
  [[ $persist =~ ^[Yy]$ ]] || return

  if has networkmanager && [[ -n $(nmcli -t dev | grep "^$iface:") ]]; then
    local conn=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v i="$iface" '$2==i{print $1}')
    if [[ $conn ]]; then
      sudo nmcli con mod "$conn" 802-3-ethernet.mtu "$opt"
      echo "Persistent via NetworkManager: $conn"
    fi
  elif [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml &>/dev/null>/dev/null; then
    local netplan_file=$(ls /etc/netplan/*.yaml | head -1)
    echo "Updating Netplan config: $netplan_file"
    if grep -q "mtu:" "$netplan_file" 2>/dev/null; then
      sudo sed -i "s/mtu: [0-9]*/mtu: $opt/" "$netplan_file"
    else
      echo "  Add 'mtu: $opt' under the $iface interface in $netplan_file"
    fi
    sudo netplan apply &>/dev/null>/dev/null || echo "Run 'sudo netplan apply' to activate"
    echo "Persistent via Netplan: $netplan_file"
  elif [[ -d /etc/systemd/network ]]; then
    local nwfile="/etc/systemd/network/99-$iface-mtu.network"
    sudo tee "$nwfile" &>/dev/null>/dev/null <<EOF
[Match]
Name=$iface

[Link]
MTUBytes=$opt
EOF
    sudo systemctl restart systemd-networkd &>/dev/null>/dev/null || :
    echo "Persistent via systemd-networkd: $nwfile"
  else
    echo "Manual persistence needed - add to /etc/network/interfaces"
  fi
}

usage(){
  cat <<EOF
Usage: ${"$0"##*/} [SERVER]
Find optimal MTU via binary search to SERVER (default: 8.8.8.8)
Supports both IPv4 and IPv6 addresses.

Options:
  -h    Show this help

Examples:
  ${"$0"##*/}              # Test to 8.8.8.8 (IPv4)
  ${"$0"##*/} 1.1.1.1      # Test to Cloudflare DNS (IPv4)
  ${"$0"##*/} 2606:4700:4700::1111  # Test to Cloudflare DNS (IPv6)
EOF
  exit 0
}

[[ ${1:-} =~ ^(-h|--help)$ ]] && usage
find_mtu "${1:-8.8.8.8}"
