#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Setup environment
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive

# UID/GID >= 100 (or <1000 for system account)
uid=200
gid=200

# Create group, user, and home directory
echo "Creating copyparty user and group..."
if ! getent group copyparty > /dev/null; then
  echo "copyparty:x:$gid:" | sudo tee -a /etc/group > /dev/null
fi
if ! getent passwd copyparty > /dev/null; then
  echo "copyparty:x:$uid:$gid:Copyparty user:/var/lib/copyparty:/sbin/nologin" | sudo tee -a /etc/passwd > /dev/null
  echo "copyparty:!::0:99999:7:::" | sudo tee -a /etc/shadow > /dev/null
fi

# Create home dir
sudo mkdir -p /var/lib/copyparty
sudo chown "$uid":"$gid" /var/lib/copyparty

# python3 /usr/local/bin/copyparty-en.py -e2dsa --ftp 3921 -z -i unix:777:/dev/shm/party.sock
bg_run() {
  nohup "$@" > /dev/null 2>&1 < /dev/null &
  disown
}
bg_fullrun() {
  nohup setsid "$@" > /dev/null 2>&1 < /dev/null &
  disown
}

bg_run python3 /usr/local/bin/copyparty-en.py -e2dsa --ftp 3921 -z -i unix:777:/dev/shm/party.sock
bg_fullrun python3 /usr/local/bin/copyparty-en.py -e2dsa --ftp 3921 -z -i unix:777:/dev/shm/party.sock
