#!/usr/bin/env bash
# Setup Copyparty with network access and Samba support
set -euo pipefail

readonly COPYPARTY_PORT=3923
readonly COPYPARTY_DIR="$HOME/Public"

echo "Setting up Copyparty with network access and Samba support..."

# Install necessary packages
echo "Installing packages..."
if ! sudo pacman -Syu --noconfirm copyparty samba avahi nss-mdns; then
  echo "Error: Failed to install required packages" >&2
  exit 1
fi

# Create config directory if it doesn't exist
mkdir -p ~/.config/copyparty

# Configure copyparty
cat > ~/.config/copyparty/config.py << 'EOF'
#!/usr/bin/env python3
"""copyparty config"""

# Get local IP address
import socket

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        IP = s.getsockname()[0]
    except Exception:
        IP = "127.0.0.1"
    finally:
        s.close()
    return IP

LOCAL_IP = get_local_ip()

# Server configuration
CFG = {
    "addr": [f"{LOCAL_IP}:3923"],  # Listen on local IP, port 3923
    "vols": {
        "~": {
            "path": "~/Public",  # Share content from ~/Public
            "auth": "any",       # Allow any access
            "perm": "ro",        # Read-only by default
        },
        "upload": {
            "path": "~/Public/uploads",
            "auth": "any",
            "perm": "wo"         # Write-only area for uploads
        },
        "share": {
            "path": "~/Public/share",
            "auth": "any",
            "perm": "rw"         # Read-write area for sharing
        }
    },
    "smbscan": True,         # Enable SMB scanning
    "smbsrv": True,          # Enable SMB server
}

# Add admin user - change this password!
users = {
    "admin": {
        "pass": "changeThisPassword",
        "perm": "*:rwm",       # Admin has all permissions
    }
}
EOF

chmod +x ~/.config/copyparty/config.py

# Create necessary directories
mkdir -p ~/Public/uploads ~/Public/share

# Configure Samba
echo "Configuring Samba..."
CURRENT_USER="$(whoami)"
sudo tee /etc/samba/smb.conf > /dev/null << EOF
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

# Create systemd user service for copyparty
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/copyparty.service << 'EOF'
[Unit]
Description=Copyparty web server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/copyparty -c %h/.config/copyparty/config.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Enable and start services
echo "Enabling and starting services..."
if ! sudo systemctl enable --now smb nmb avahi-daemon; then
  echo "Warning: Failed to enable some system services" >&2
fi

systemctl --user daemon-reload
systemctl --user enable copyparty.service
if ! systemctl --user start copyparty.service; then
  echo "Error: Failed to start copyparty service" >&2
  echo "Check logs with: systemctl --user status copyparty.service" >&2
  exit 1
fi

# Allow systemd user services to run without being logged in
sudo loginctl enable-linger "$(whoami)"

# Configure firewall if it's active
if systemctl is-active --quiet firewalld; then
  echo "Configuring firewalld..."
  sudo firewall-cmd --permanent --add-service=samba
  sudo firewall-cmd --permanent --add-port="$COPYPARTY_PORT"/tcp
  sudo firewall-cmd --reload
elif systemctl is-active --quiet ufw; then
  echo "Configuring ufw..."
  sudo ufw allow "$COPYPARTY_PORT"/tcp
  sudo ufw allow Samba
fi

# Get local IP for the user
IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)

echo ""
echo "=============================================="
echo "Copyparty setup complete!"
echo "=============================================="
echo "Access your Copyparty instance at: http://${IP}:${COPYPARTY_PORT}"
echo ""
echo "IMPORTANT: Change the admin password in ~/.config/copyparty/config.py"
echo "After changing the password, restart the service:"
echo "  systemctl --user restart copyparty.service"
echo ""
echo "Check service status with:"
echo "  systemctl --user status copyparty.service"
echo "=============================================="
