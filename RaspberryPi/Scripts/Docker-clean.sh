#!/usr/bin/env bash
# Optimized: 2025-11-21 - Applied bash optimization techniques
# Set shell options:
#   -e, exit immediately if a command exits with a non-zero status
#   -o pipefail, means that if any element of the pipeline fails, then the pipeline as a whole will fail.
#   -u, treat unset variables as an error when substituting.
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-${USER:-$(id -un)}}" DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
DONT_RESTART_DOCKER_ENGINE=0 DONT_ASK_CONFIRMATION=0
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --no-restart)
      DONT_RESTART_DOCKER_ENGINE=1
      shift
      ;;
    -y)
      DONT_ASK_CONFIRMATION=1
      shift
      ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
  esac
done
# Asks user for confirmation interactively
ask_user_for_confirmation(){
  cat << EOF
==============================================
This script reclaims disk space by removing stale and unused Docker data:
 > removes stopped containers
 > removes orphan (dangling) images layers
 > removes unused volumes
 > removes Docker build cache
 > shrinks the "Docker.raw" file on MacOS
 > restarts the Docker engine
 > prints Docker disk usage
==============================================
EOF
  [[ $DONT_ASK_CONFIRMATION -eq 1 ]] && return
  read -p "Would you like to proceed (y/n)? " confirmation
  # Stop if answer is anything but "Y" or "y"
  [[ $confirmation == "${confirmation#[Yy]}" ]] && exit 1
}
# On MacOS, restarting Docker Desktop for Mac might take a long time
poll_for_docker_readiness(){
  printf 'Waiting for docker engine to start:\n'
  local i=0
  while ! docker system info &>/dev/null; do
    printf '%*s\n' "$i" '' | tr ' ' '.'
    i=$((i + 1))
    sleep 1
    tput el
  done
  printf '\n\n'
}
# Checks if a particular program is installed
is_program_installed(){ command -v "$1" &>/dev/null; }
# Restarts the Docker engine
restart_docker_engine(){
  [[ $DONT_RESTART_DOCKER_ENGINE -eq 1 ]] && return
  echo "👉 Restarting Docker engine"
  sudo systemctl stop docker.service || :
  sudo systemctl start docker.service
}
echo "👉 Docker disk usage"
docker system df
ask_user_for_confirmation
echo "👉 Remove all stopped containers"
docker ps --filter "status=exited" -q | xargs -r docker rm --force
echo "👉 Remove all orphan image layers"
docker images -f "dangling=true" -q | xargs -r docker rmi -f
echo "👉 Remove all unused volumes"
docker volume ls -qf dangling=true | xargs -r docker volume rm
echo "👉 Remove Docker builder cache"
DOCKER_BUILDKIT=1 docker builder prune -af
echo "👉 Remove networks not used by at least one container"
docker network prune -f
echo "👉 Remove unused volumes"
# -a, --all, Remove all unused build cache, not just dangling ones
docker system prune -af --volumes
#docker image prune -a -f
#docker volume prune -f
#docker system prune -a -f
docker-remove-stale-assets
echo "👉 Docker disk usage (after cleanup)"
docker system df
restart_docker_engine
# https://github.com/docker-slim/docker-slim
docker-slim(){
  if [[ $# -eq 0 ]]; then
    sudo docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock dslim/docker-slim help
  else
    sudo docker run -it --rm -v /var/run/docker.sock:/var/run/docker.sock dslim/docker-slim "$@"
  fi
}
echo "🤘 Done"
