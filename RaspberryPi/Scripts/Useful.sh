#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/text.sh"

# Setup environment
setup_environment

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

remove_comments() {
  printf '%b' "${BLUE}removing comments${NC}"
  awk '!/^#/' "$current_dir/$newhostsfn" >tmp \
    && mv -f tmp "$current_dir/$newhostsfn" \
    && printf '%b' "${BLUE}: ${GREEN}done${NC}"
}
remove_duplicate_lines() {
  printf '%b' "${BLUE}removing duplicate lines${NC}"
  awk '!seen[$0]++' "$current_dir/$newhostsfn" >tmp \
    && mv -f tmp "$current_dir/$newhostsfn" \
    && printf '%b\n' "${BLUE}: ${GREEN}done${NC}"
}
remove_trailing_spaces() {
  printf '%b' "${BLUE}removing trailing spaces${NC}"
  awk '{gsub(/^ +| +$/,"")}1' "$current_dir/$newhostsfn" >tmp \
    && mv -f tmp "$current_dir/$newhostsfn" \
    && printf '%b' "${BLUE}: ${GREEN}done${NC}"
}
edithostsfile() {
  remove_comments
  remove_trailing_spaces
  remove_duplicate_lines
}
