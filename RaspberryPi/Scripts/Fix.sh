#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Setup environment
setup_environment

sudo apt-get install ntpdate
sudo ntpdate -u ntp.ubuntu.com
sudo apt-get install ca-certificates

# SSH fix - Set proper permissions using find with fallback
find_with_fallback f "*" ~/.ssh/ -exec chmod 600 {} +
find_with_fallback d "*" ~/.ssh/ -exec chmod 700 {} +
find_with_fallback f "*.pub" ~/.ssh/ -exec chmod 644 {} +

sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg

# Nextcloud CasaOS fix
sudo docker exec nextcloud ls -ld /tmp
sudo docker exec nextcloud chown -R www-data:www-data /tmp
sudo docker exec nextcloud chmod -R 755 /tmp
sudo docker exec nextcloud ls -ld /tmp
