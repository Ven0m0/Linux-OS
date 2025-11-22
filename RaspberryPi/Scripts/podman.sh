#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive

sudo apt-get update -y
sudo apt-get install -y podman podman-docker
sudo touch /etc/containers/nodocker
sudo systemctl daemon-reload
sudo systemctl enable --now podman.socket
# ensure /var/run exists
sudo mkdir -p /var/run
# create tmpfiles entry to create symlink each boot
sudo tee /etc/tmpfiles.d/podman-docker.conf >/dev/null <<'EOF'
# Type Path         Mode UID  GID Age Argument
L    /var/run/docker.sock -    -    -    -    /run/podman/podman.sock
EOF
# create docker.service that runs podman system service on /var/run/docker.sock
sudo tee /etc/systemd/system/docker.service >/dev/null <<'EOF'
[Unit]
Description=Podman Docker-compat service
After=network.target podman.socket
Wants=podman.socket

[Service]
Type=simple
# create symlink (idempotent) before starting service
ExecStartPre=/bin/ln -sf /run/podman/podman.sock /var/run/docker.sock
ExecStart=/usr/bin/podman system service -t 0 unix:///var/run/docker.sock
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload &>/dev/null>/dev/null || :
sudo systemctl enable --now docker.service &>/dev/null>/dev/null || :

# podman-compose: try apt first, otherwise pip (user install)
if ! command -v podman-compose &>/dev/null>/dev/null; then
  sudo apt-get install -y podman-compose &>/dev/null>/dev/null || :
fi
if ! command -v podman-compose &>/dev/null>/dev/null; then
  uv pip install -U podman-compose || python3 -m pip install --upgrade --user podman-compose
  ln -sf /root/.local/bin/podman-compose /usr/local/bin/podman-compose || :
fi
if ! command -v docker &>/dev/null>/dev/null; then
  printf 'warning: docker CLI not found; podman-docker package likely failed to install\n' >&2
fi
export DOCKER_HOST=unix:///run/podman/podman.sock
# final: friendly status lines (concise)
printf 'podman.socket: %s\n' "$(systemctl is-active podman.socket 2>/dev/null || echo inactive)"
printf 'docker.service: %s\n' "$(systemctl is-active docker.service 2>/dev/null || echo inactive)"
printf '/var/run/docker.sock -> %s\n' "$(readlink -f /var/run/docker.sock 2>/dev/null || echo missing)"
printf 'podman version: %s\n' "$(podman version --format json 2>/dev/null | head -c200 || echo unavailable)"
printf 'podman-compose: %s\n' "$(command -v podman-compose || echo missing)"
# Run docker-compose up if docker-compose.yml exists in current directory
[[ -f docker-compose.yml ]] && docker-compose up || echo "No docker-compose.yml found in current directory"
