#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1

yes | sudo apt-get update -y --fix-missing
yes | sudo apt-get upgrade -y

setup-podman() {
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
  sudo systemctl daemon-reload &>/dev/null || :
  sudo systemctl enable --now docker.service &>/dev/null || :
  # podman-compose: try apt first, otherwise pip (user install)
  if ! command -v podman-compose &>/dev/null; then
    sudo apt-get install -y podman-compose &>/dev/null || :
  fi
  if ! command -v podman-compose &>/dev/null; then
    uv pip install -U podman-compose || python3 -m pip install --upgrade --user podman-compose
    ln -sf /root/.local/bin/podman-compose /usr/local/bin/podman-compose || :
  fi
  if ! command -v docker &>/dev/null; then
    printf 'warning: docker CLI not found; podman-docker package likely failed to install\n' >&2
  fi
  export DOCKER_HOST=unix:///run/podman/podman.sock
  # final: friendly status lines
  printf 'podman.socket: %s\n' "$(systemctl is-active podman.socket 2>/dev/null || echo inactive)"
  printf 'docker.service: %s\n' "$(systemctl is-active docker.service 2>/dev/null || echo inactive)"
  printf '/var/run/docker.sock -> %s\n' "$(readlink -f /var/run/docker.sock 2>/dev/null || echo missing)"
  printf 'podman version: %s\n' "$(podman version --format json 2>/dev/null | head -c200 || echo unavailable)"
  printf 'podman-compose: %s\n' "$(command -v podman-compose || echo missing)"
  # Run docker-compose up if docker-compose.yml exists in current directory
  [[ -f docker-compose.yml ]] && docker-compose up || echo "No docker-compose.yml found in current directory"
}
setup-docker() {
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
  echo "Configuring systemd-resolved for Docker..."
  sudo mkdir -p /etc/systemd/resolved.conf.d
  printf '[Resolve]\nDNSStubListenerExtra=172.17.0.1\n' | sudo tee /etc/systemd/resolved.conf.d/20-docker-dns.conf >/dev/null
  sudo systemctl restart systemd-resolved
  echo "Enabling Docker service..."
  sudo systemctl enable --now docker
  echo "Adding user to docker group..."
  sudo usermod -aG docker "$USER"
  echo "Configuring Docker systemd unit..."
  sudo mkdir -p /etc/systemd/system/docker.service.d
  sudo tee /etc/systemd/system/docker.service.d/no-block-boot.conf >/dev/null <<'EOF'
[Unit]
DefaultDependencies=no
EOF
  sudo systemctl daemon-reload
  echo "Docker configuration complete!"
  echo "Note: You may need to log out and back in for group changes to take effect."
}
setup-podman || setup-docker
