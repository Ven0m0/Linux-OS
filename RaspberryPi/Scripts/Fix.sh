#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# Setup environment
setup_environment

sudo apt-get install ntpdate
sudo ntpdate -u ntp.ubuntu.com
sudo apt-get install ca-certificates

# SSH fix - Use fd/fdf when available for better performance
if command -v fdf &>/dev/null; then
  fdf -H -t f . ~/.ssh/ -x chmod 600
  fdf -H -t d . ~/.ssh/ -x chmod 700
  fdf -H -t f '\.pub$' ~/.ssh/ -x chmod 644
elif command -v fd &>/dev/null; then
  fd -H -t f . ~/.ssh/ -x chmod 600
  fd -H -t d . ~/.ssh/ -x chmod 700
  fd -H -t f '\.pub$' ~/.ssh/ -x chmod 644
else
  find ~/.ssh/ -type f -exec chmod 600 {} +
  find ~/.ssh/ -type d -exec chmod 700 {} +
  find ~/.ssh/ -type f -name "*.pub" -exec chmod 644 {} +
fi

sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg

# Nextcloud CasaOS fix
sudo docker exec nextcloud ls -ld /tmp
sudo docker exec nextcloud chown -R www-data:www-data /tmp
sudo docker exec nextcloud chmod -R 755 /tmp
sudo docker exec nextcloud ls -ld /tmp
