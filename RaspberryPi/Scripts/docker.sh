#!/usr/bin/env bash
# Optimized: 2025-11-22 - Applied bash optimization techniques
# DESCRIPTION: Configure Docker daemon with optimized settings

set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Configure Docker daemon:
# - limit log size to avoid running out of disk
# - use host's DNS resolver
echo "Configuring Docker daemon..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": { "max-size": "10m", "max-file": "5" },
    "dns": ["172.17.0.1"],
    "bip": "172.17.0.1/16"
}
EOF

# Expose systemd-resolved to our Docker network
echo "Configuring systemd-resolved for Docker..."
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNSStubListenerExtra=172.17.0.1\n' | sudo tee /etc/systemd/resolved.conf.d/20-docker-dns.conf >/dev/null
sudo systemctl restart systemd-resolved

# Start Docker automatically
echo "Enabling Docker service..."
sudo systemctl enable docker

# Give this user privileged Docker access
echo "Adding user to docker group..."
sudo usermod -aG docker "$USER"

# Prevent Docker from preventing boot for network-online.target
echo "Configuring Docker systemd unit..."
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/no-block-boot.conf >/dev/null <<'EOF'
[Unit]
DefaultDependencies=no
EOF

sudo systemctl daemon-reload

echo "Docker configuration complete!"
echo "Note: You may need to log out and back in for group changes to take effect."
