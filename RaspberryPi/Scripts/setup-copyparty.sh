#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
# Setup Copyparty with network access and Samba support (Debian/Raspbian)
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
readonly COPYPARTY_PORT=3923
readonly COPYPARTY_DIR="$HOME/Public"
printf '%s\n' "Setting up Copyparty with network access and Samba support..."
# Install necessary packages (apt for Debian/Raspbian)
printf '%s\n' "Installing packages..."
sudo apt-get update && sudo apt-get install -y python3-pip samba avahi-daemon libnss-mdns || {
  printf '%s\n' "Error: Failed to install required packages" >&2
  exit 1
}
# Install copyparty via pip if not available
if ! command -v copyparty &>/dev/null; then
  printf '%s\n' "Installing copyparty via pip..."
  pip3 install --user copyparty
fi
# Create config directory
mkdir -p ~/.config/copyparty
# Configure copyparty
cat >~/.config/copyparty/config.py <<'EOF'
#!/usr/bin/env python3
"""copyparty config"""
import socket
def get_local_ip():
  s = socket.socket(socket.AF_INET, SOCK_DGRAM)
  try:
    s.connect(("8.8.8.8", 80))
    IP = s.getsockname()[0]
  except Exception:
    IP = "127.0.0.1"
  finally:
    s.close()
  return IP
LOCAL_IP = get_local_ip()
CFG = {
  "addr": [f"{LOCAL_IP}:3923"],
  "vols": {
    "~": {"path": "~/Public", "auth": "any", "perm": "ro"},
    "upload": {"path": "~/Public/uploads", "auth": "any", "perm": "wo"},
    "share": {"path": "~/Public/share", "auth": "any", "perm": "rw"}
  },
  "smbscan": True,
  "smbsrv": True,
}
users = {
  "admin": {"pass": "changeThisPassword", "perm": "*:rwm"}
}
EOF
chmod +x ~/.config/copyparty/config.py
# Create directories
mkdir -p ~/Public/uploads ~/Public/share
# Configure Samba
printf '%s\n' "Configuring Samba..."
CURRENT_USER="$(whoami)"
sudo tee /etc/samba/smb.conf >/dev/null <<EOF
[global]
  workgroup = WORKGROUP
  server string = Copyparty Samba Server
  server role = standalone server
  log file = /var/log/samba/%m.log
  max log size = 50
  dns proxy = no
  map to guest = Bad User
  usershare allow guests = yes

[copyparty]
  comment = Copyparty Shared Folders
  path = /home/${CURRENT_USER}/Public
  browseable = yes
  read only = no
  guest ok = yes
  create mask = 0644
  directory mask = 0755
EOF
# Create systemd user service
mkdir -p ~/.config/systemd/user
cat >~/.config/systemd/user/copyparty.service <<'EOF'
[Unit]
Description=Copyparty web server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/copyparty -c %h/.config/copyparty/config.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
# Enable services
printf '%s\n' "Enabling and starting services..."
sudo systemctl enable --now smbd nmbd avahi-daemon || printf '%s\n' "Warning: Failed to enable some system services" >&2
systemctl --user daemon-reload
systemctl --user enable copyparty.service
systemctl --user start copyparty.service || {
  printf '%s\n' "Error: Failed to start copyparty service" >&2
  printf '%s\n' "Check logs with: systemctl --user status copyparty.service" >&2
  exit 1
}
# Enable linger
sudo loginctl enable-linger "$(whoami)"
# Configure firewall if active
systemctl is-active --quiet ufw && {
  printf '%s\n' "Configuring ufw..."
  sudo ufw allow "$COPYPARTY_PORT"/tcp
  sudo ufw allow Samba
}
# Get local IP
IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
printf '\n%.0s' {1..2}
printf '%s\n' "=============================================="
printf '%s\n' "Copyparty setup complete!"
printf '%s\n' "=============================================="
printf '%s\n' "Access: http://${IP}:${COPYPARTY_PORT}"
printf '\n'
printf '%s\n' "IMPORTANT: Change admin password in ~/.config/copyparty/config.py"
printf '%s\n' "Then restart: systemctl --user restart copyparty.service"
printf '\n'
printf '%s\n' "Status: systemctl --user status copyparty.service"
printf '%s\n' "=============================================="
