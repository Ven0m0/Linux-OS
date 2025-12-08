#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t' LC_ALL=C LANG=C
export HOME="/home/${SUDO_USER:-$USER}"
has(){ command -v -- "$1" &> /dev/null; }
die(){
  echo "ERROR: $*" >&2
  exit 1
}
check_requirements(){
  local -a missing=() reqs=(ping ip)
  for req in "${reqs[@]}"; do
    has "$req" || missing+=("$req")
  done
  ((${#missing[@]})) && die "Missing tools: ${missing[*]}"
}
detect_ip_version(){
  local addr="$1"
  [[ $addr =~ : ]] && echo "6" || echo "4"
}
select_interface(){
  local -a ifaces
  mapfile -t ifaces < <(ip -br link | awk '$1! ~/(lo|veth|docker|br-)/{print $1}')
  ((${#ifaces[@]})) || die "No valid interfaces found"
  if ((${#ifaces[@]} == 1)); then
    echo "${ifaces[0]}"
    return
  fi
  printf "Available interfaces:\n"
  for i in "${!ifaces[@]}"; do
    printf "%d) %s\n" $((i + 1)) "${ifaces[$i]}"
  done
  local n
  read -rp "Select [1-${#ifaces[@]}]: " n
  [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#ifaces[@]} ]] || die "Invalid selection"
  echo "${ifaces[$((n - 1))]}"
}
persist_mtu(){
  local iface=$1 mtu=$2
  if has nmcli && [[ -n $(nmcli -t dev | grep "^$iface:") ]]; then
    local conn
    conn=$(nmcli -t -f NAME,DEVICE con show --active | awk -F: -v i="$iface" '$2==i{print $1}')
    if [[ $conn ]]; then
      sudo nmcli con mod "$conn" 802-3-ethernet.mtu "$mtu"
      echo "Persistent via NetworkManager: $conn"
      return 0
    fi
  fi
  if [[ -d /etc/netplan ]] && compgen -G "/etc/netplan/*.yaml" > /dev/null; then
    local netplan_file
    netplan_file=$(compgen -G "/etc/netplan/*. yaml" | head -1)
    echo "Updating Netplan config: $netplan_file"
    if grep -q "^ *$iface:" "$netplan_file" 2> /dev/null; then
      if grep -q "mtu:" "$netplan_file" 2> /dev/null; then
        sudo sed -i "s/mtu: [0-9]*/mtu: $mtu/" "$netplan_file"
      else
        sudo sed -i "/^ *$iface:/a\      mtu: $mtu" "$netplan_file"
      fi
      sudo netplan apply &> /dev/null || echo "Run 'sudo netplan apply' to activate"
      echo "Persistent via Netplan: $netplan_file"
      return 0
    fi
  fi
  if [[ -d /etc/systemd/network ]]; then
    local nwfile="/etc/systemd/network/99-$iface-mtu. network"
    sudo tee "$nwfile" &> /dev/null << EOF
[Match]
Name=$iface

[Link]
MTUBytes=$mtu
EOF
    sudo systemctl restart systemd-networkd &> /dev/null || :
    echo "Persistent via systemd-networkd: $nwfile"
    return 0
  fi
  if [[ -f /etc/network/interfaces ]]; then
    if grep -q "iface $iface inet" /etc/network/interfaces 2> /dev/null; then
      if grep -q "^ *mtu $iface" /etc/network/interfaces 2> /dev/null; then
        sudo sed -i "/iface $iface inet/,/^iface/ s/^ *mtu . */    mtu $mtu/" /etc/network/interfaces
      else
        sudo sed -i "/iface $iface inet/ a\    mtu $mtu" /etc/network/interfaces
      fi
      echo "Persistent via /etc/network/interfaces"
      sudo systemctl restart networking &> /dev/null || sudo ifdown "$iface" && sudo ifup "$iface" || :
      return 0
    fi
  fi
  echo "Manual persistence needed - no supported network manager found"
}

find_mtu_binary(){
  local srv="$1" iface="$2" lo=1200 hi=1500 mid opt ipver overhead ping_cmd
  ipver=$(detect_ip_version "$srv")
  if [[ $ipver == "6" ]]; then
    overhead=48
    ping_cmd="ping6"
    has ping6 || die "ping6 not available for IPv6"
  else
    overhead=28
    ping_cmd="ping"
  fi
  echo "Testing MTU to $srv (IPv$ipver) via binary search..."
  "$ping_cmd" -c1 -W1 "$srv" &> /dev/null || die "Server $srv unreachable"
  "$ping_cmd" -M 'do' -s$((lo - overhead)) -c1 "$srv" &> /dev/null || die "Min MTU $lo not viable"
  opt=$lo
  while ((lo <= hi)); do
    mid=$(((lo + hi) / 2))
    if "$ping_cmd" -M 'do' -s$((mid - overhead)) -c1 "$srv" &> /dev/null; then
      opt="$mid"
      lo=$((mid + 1))
    else
      hi=$((mid - 1))
    fi
  done
  opt=$((opt - 4))
  echo "Optimal MTU: $opt bytes (4-byte safety margin)"
  echo "$opt"
}

find_mtu_incremental(){
  local srv="$1" iface="$2" step="$3" current last_ok min_mtu=1000 max_mtu=1500 ipver overhead ping_cmd
  ipver=$(detect_ip_version "$srv")
  if [[ $ipver == "6" ]]; then
    overhead=48
    ping_cmd="ping6"
    has ping6 || die "ping6 not available for IPv6"
  else
    overhead=28
    ping_cmd="ping"
  fi
  echo "Testing MTU to $srv (IPv$ipver) via incremental (step=$step)..."
  "$ping_cmd" -c1 -W1 "$srv" &> /dev/null || die "Server $srv unreachable"
  sudo ip link set dev "$iface" mtu "$max_mtu" &> /dev/null || die "Cannot set initial MTU"
  current="$min_mtu"
  last_ok="$min_mtu"
  while ((current <= max_mtu)); do
    printf "Testing MTU: %d...  " "$current"
    if "$ping_cmd" -M 'do' -s$((current - overhead)) -c1 -W1 "$srv" &> /dev/null; then
      echo "OK"
      last_ok="$current"
    else
      echo "FAIL - retrying..."
      read -rt 0.5 -- <> <(:) &> /dev/null || :
      if "$ping_cmd" -M 'do' -s$((current - overhead)) -c1 -W1 "$srv" &> /dev/null; then
        echo "  Retry OK"
        last_ok="$current"
      else
        echo "  Retry FAIL - stopping"
        break
      fi
    fi
    ((current += step))
  done
  last_ok=$((last_ok - 2))
  echo "Optimal MTU: $last_ok bytes (2-byte safety margin)"
  echo "$last_ok"
}

main(){
  local srv step_mode=0 step_size=5 iface opt choice persist_choice
  check_requirements
  while getopts "s:h" opt; do
    case $opt in
      s)
        step_mode=1 step_size="$OPTARG"
        [[ $step_size =~ ^[0-9]+$ && $step_size -ge 1 && $step_size -le 10 ]] || die "Step size must be 1-10"
        ;;
      h)
        cat << EOF
Usage: ${0##*/} [-s STEP] [SERVER]
Find optimal MTU to SERVER (default: 8.8.8.8)
Supports IPv4 and IPv6.

Options:
  -s STEP   Use incremental mode with step size 1-10 (default: binary search)
  -h        Show this help

Examples:
  ${0##*/}                       # Binary search to 8.8.8.8
  ${0##*/} 1.1.1.1               # Binary search to Cloudflare
  ${0##*/} -s 5 1.1.1.1          # Incremental (step=5)
  ${0##*/} 2606:4700:4700::1111  # IPv6 binary search
EOF
        exit 0
        ;;
      *) die "Invalid option.  Use -h for help" ;;
    esac
  done
  shift $((OPTIND - 1))
  srv=${1:-8.8.8.8}
  read -rp "Set MTU on interface?  (Y/n) " -n1 choice
  [[ $choice =~ ^[Nn]$ ]] && {
    echo "Dry run only - no changes applied"
    iface="(not selected)"
    if ((step_mode)); then
      find_mtu_incremental "$srv" "$iface" "$step_size" > /dev/null
    else
      find_mtu_binary "$srv" "$iface" > /dev/null
    fi
    return 0
  }
  iface=$(select_interface)
  echo "Selected interface: $iface"
  local mtu
  if ((step_mode)); then
    mtu=$(find_mtu_incremental "$srv" "$iface" "$step_size")
  else
    mtu=$(find_mtu_binary "$srv" "$iface")
  fi
  sudo ip link set dev "$iface" mtu "$mtu" || die "Failed to set MTU on $iface"
  echo "MTU set to $mtu on $iface"
  read -rp "Make persistent? (y/N) " -n1 persist_choice
  [[ $persist_choice =~ ^[Yy]$ ]] && persist_mtu "$iface" "$mtu"
}

main "$@"
