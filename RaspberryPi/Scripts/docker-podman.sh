#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar 
LC_ALL=C DEBIAN_FRONTEND=noninteractive

sudo apt-get update  
sudo apt-get install -y podman podman-docker
sudo touch /etc/containers/nodocker  
systemctl enable --now podman.socket
export DOCKER_HOST=unix:///run/podman/podman.sock  
docker-compose up
