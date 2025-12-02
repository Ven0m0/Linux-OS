#!/usr/bin/env bash
# Optimized: 2025-11-22 - Applied bash optimization techniques

# Source shared libraries
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/../../lib/core.sh"
# shellcheck source=lib/debian.sh
source "$SCRIPT_DIR/../../lib/debian.sh"

sudo apt-get install ntpdate
sudo ntpdate -u ntp.ubuntu.com
sudo apt-get install ca-certificates

# SSH fix - Set proper permissions using find with fallback
if [[ -d ~/.ssh ]]; then
  find_with_fallback f "*" ~/.ssh/ -exec chmod 600 {} +
  find_with_fallback d "*" ~/.ssh/ -exec chmod 700 {} +
  find_with_fallback f "*.pub" ~/.ssh/ -exec chmod 644 {} +
fi

# Fix permissions (700 for directories, 600 for files is more secure than 744)
[[ -d ~/.ssh ]] && sudo chmod 700 ~/.ssh
[[ -d ~/.gnupg ]] && sudo chmod 700 ~/.gnupg

# Nextcloud CasaOS fix
sudo docker exec nextcloud ls -ld /tmp
sudo docker exec nextcloud chown -R www-data:www-data /tmp
sudo docker exec nextcloud chmod -R 755 /tmp
sudo docker exec nextcloud ls -ld /tmp
