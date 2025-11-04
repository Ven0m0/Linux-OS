#!/usr/bin/env bash
set -euo pipefail
has(){ command -v -- "$1" &>/dev/null; }
die(){ echo "ERROR: $*" >&2; exit 1; }

find_mtu(){
  local srv=${1:-8.8.8.8} lo=1200 hi=1500 mid opt iface
  
  echo "Testing MTU to $srv..."
  ping -c1 -W1 "$srv" &>/dev/null || die "Server $srv unreachable"
  ping -M do -s$((lo-28)) -c1 "$srv" &>/dev/null || die "Min MTU $lo not viable"
  
  opt=$lo
  while ((lo<=hi)); do
    mid=$(((lo+hi)/2))
    if ping -M do -s$((mid-28)) -c1 "$srv" &>/dev/null 2>&1; then
      opt=$mid
      lo=$((mid+1))
    else
      hi=$((mid-1))
    fi
  done
  
  echo "Optimal MTU: $opt bytes"
  
  read -rp "Set MTU on interface? (Y/n) " -n1 choice
  echo
  [[ $choice =~ ^[Nn]$ ]] && { echo "Skipped"; return; }
  
  mapfile -t ifaces < <(ip -br link | awk '$1!~/(lo|veth|docker)/{print $1}')
  ((${#ifaces[@]})) || die "No interfaces found"
  
  if ((${#ifaces[@]}==1)); then
    iface=${ifaces[0]}
  else
    echo -e "\nAvailable interfaces:"
    for i in "${!ifaces[@]}"; do
      printf "%d) %s\n" $((i+1)) "${ifaces[$i]}"
    done
    read -rp "Select [1-${#ifaces[@]}]: " n
    [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#ifaces[@]} ]] || die "Invalid selection"
    iface=${ifaces[$((n-1))]}
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
  elif [[ -d /etc/systemd/network ]]; then
    local nwfile="/etc/systemd/network/99-$iface-mtu.network"
    sudo tee "$nwfile" &>/dev/null <<EOF
[Match]
Name=$iface

[Link]
MTUBytes=$opt
EOF
    sudo systemctl restart systemd-networkd &>/dev/null || :
    echo "Persistent via systemd-networkd: $nwfile"
  else
    echo "Manual persistence needed - add to /etc/network/interfaces or netplan"
  fi
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [SERVER]
Find optimal MTU via binary search to SERVER (default: 8.8.8.8)

Options:
  -h    Show this help
  
Examples:
  $(basename "$0")              # Test to 8.8.8.8
  $(basename "$0") 1.1.1.1      # Test to Cloudflare DNS
EOF
  exit 0
}

[[ ${1:-} =~ ^(-h|--help)$ ]] && usage
find_mtu "${1:-8.8.8.8}"
