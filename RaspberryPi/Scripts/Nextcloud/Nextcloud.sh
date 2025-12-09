#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
# Optimized: 2025-11-21 - Applied bash optimization techniques
#
# Configuration:
# Set these environment variables before running to customize the installation:
#   NEXTCLOUD_DOMAIN - Your Nextcloud domain (default: cloud.example.com)
#   DB_NAME          - Database name (default: nextcloud)
#   DB_USER          - Database user (default: ncuser)
#   DB_PASS          - Database password (default: auto-generated)
#   TIMEZONE         - System timezone (default: UTC)
#
# Example usage:
#   NEXTCLOUD_DOMAIN=mycloud.example.com TIMEZONE=America/New_York ./Nextcloud.sh
#
# Source shared libraries
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# ============ Inlined from lib/common.sh ============
export LC_ALL=C LANG=C
export DEBIAN_FRONTEND=noninteractive
export HOME="/home/${SUDO_USER:-$USER}"
set -euo pipefail
shopt -s nullglob globstar execfail
IFS=$'
 '
has(){ command -v -- "$1" &>/dev/null; }
hasname(){
  local x
  if ! x=$(type -P -- "$1"); then return 1; fi
  printf '%s
' "${x##*/}"
}
is_program_installed(){ command -v "$1" &>/dev/null; }
get_workdir(){
  local script="${BASH_SOURCE[1]:-$0}"
  builtin cd -- "${-- "$script"%/*}" && printf '%s
' "$PWD"
}
init_workdir(){
  local workdir
  workdir="$(builtin cd -- "${-- "${BASH_SOURCE[1]:-}"%/*}" && printf '%s
' "$PWD")"
  cd "$workdir" || {
    echo "Failed to change to working directory: $workdir" >&2
    exit 1
  }
}
require_root(){ if [[ $EUID -ne 0 ]]; then
  local script_path
  script_path=$([[ ${BASH_SOURCE[1]:-$0} == /* ]] && echo "${BASH_SOURCE[1]:-$0}" || echo "$PWD/${BASH_SOURCE[1]:-$0}")
  sudo "$script_path" "$@" || {
    echo 'Administrator privileges are required.' >&2
    exit 1
  }
  exit 0
fi; }
check_root(){ if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi; }
load_dietpi_globals(){ [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
run_dietpi_cleanup(){ if [[ -f /boot/dietpi/func/dietpi-logclear ]]; then
  if ! sudo dietpi-update 1 && ! sudo /boot/dietpi/dietpi-update 1; then echo "Warning: dietpi-update failed (both standard and fallback commands)." >&2; fi
  sudo /boot/dietpi/func/dietpi-logclear 2 2>/dev/null || G_SUDO dietpi-logclear 2 2>/dev/null || :
  sudo /boot/dietpi/func/dietpi-cleaner 2 2>/dev/null || G_SUDO dietpi-cleaner 2 2>/dev/null || :
fi; }
setup_environment(){
  set -euo pipefail
  shopt -s nullglob globstar execfail
  IFS=$'
 '
}
get_sudo_cmd(){
  local sudo_cmd
  sudo_cmd="$(hasname sudo-rs || hasname sudo || hasname doas)" || {
    echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
    return 1
  }
  printf '%s
' "$sudo_cmd"
}
init_sudo(){
  local sudo_cmd
  sudo_cmd="$(get_sudo_cmd)" || return 1
  if [[ $EUID -ne 0 && $sudo_cmd =~ ^(sudo-rs|sudo)$ ]]; then "$sudo_cmd" -v 2>/dev/null || :; fi
}
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fdf; then fdf -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; elif has fd; then fd -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"; else
    local find_type_arg
    case "$ftype" in f) find_type_arg="-type f" ;; d) find_type_arg="-type d" ;; l) find_type_arg="-type l" ;; *) find_type_arg="-type f" ;; esac
    if [[ -n $action ]]; then find "$search_path" "$find_type_arg" -name "$pattern" "$action" "$@"; else find "$search_path" "$find_type_arg" -name "$pattern"; fi
  fi
}
# ============ End of inlined lib/common.sh ============

# Setup environment
setup_environment

sudo apt-get update && sudo apt-get upgrade -y

# Configuration variables - CUSTOMIZE THESE
NEXTCLOUD_DOMAIN="${NEXTCLOUD_DOMAIN:-cloud.example.com}"
DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-ncuser}"
DB_PASS="${DB_PASS:-$(openssl rand -base64 32)}" # Generate random password
TIMEZONE="${TIMEZONE:-UTC}"

echo "=== Nextcloud Installation Script ==="
echo "Domain: $NEXTCLOUD_DOMAIN"
echo "Database: $DB_NAME"
echo "DB User: $DB_USER"
echo "DB Password: (generated)"
echo "Timezone: $TIMEZONE"
echo ""
read -p "Proceed with installation? (y/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && {
  echo "Installation cancelled"
  exit 0
}

# Install Nginx, MariaDB, PHP-FPM and required PHP modules
echo "Installing dependencies..."
sudo apt-get install -y nginx mariadb-server \
  php-fpm php-mysql php-cli php-zip php-xml php-mbstring php-curl php-gd \
  php-bcmath php-gmp php-intl php-imagick php-apcu php-redis \
  zip unzip wget curl openssl redis-server

# Find PHP version
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI="/etc/php/$PHP_VERSION/fpm/php.ini"

if [[ -f $PHP_INI ]]; then
  echo "Configuring PHP ($PHP_INI)..."
  sudo sed -i "s/memory_limit = .*/memory_limit = 512M/" "$PHP_INI"
  sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 512M/" "$PHP_INI"
  sudo sed -i "s/post_max_size = .*/post_max_size = 512M/" "$PHP_INI"
  sudo sed -i "s/max_execution_time = .*/max_execution_time = 300/" "$PHP_INI"
  sudo sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" "$PHP_INI"
  sudo sed -i "s|;date.timezone =|date.timezone = $TIMEZONE|" "$PHP_INI"
  sudo systemctl restart "php$PHP_VERSION-fpm"
fi

# Secure MariaDB
echo "Securing MariaDB..."
sudo mysql_secure_installation

# Create database and user
echo "Creating Nextcloud database..."
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Create Nextcloud directory if it doesn't exist
if [[ ! -d /var/www/nextcloud ]]; then
  echo "WARNING: /var/www/nextcloud does not exist. Please download and extract Nextcloud first."
  echo "Visit: https://nextcloud.com/install/"
else
  sudo chown -R www-data:www-data /var/www/nextcloud
  sudo chmod -R 755 /var/www/nextcloud
fi

# Install certbot for SSL
echo "Installing certbot..."
sudo apt-get install -y certbot python3-certbot-nginx

echo ""
echo "=== Installation Summary ==="
echo "Database credentials saved to: /root/.nextcloud-db-credentials"
sudo tee /root/.nextcloud-db-credentials >/dev/null <<CREDS
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
CREDS
sudo chmod 600 /root/.nextcloud-db-credentials

echo ""
echo "=== Next Steps ==="
echo "1. Configure Nginx: sudo nano /etc/nginx/sites-available/nextcloud.conf"
echo "2. Enable site: sudo ln -s /etc/nginx/sites-available/nextcloud.conf /etc/nginx/sites-enabled/"
echo "3. Test config: sudo nginx -t"
echo "4. Reload Nginx: sudo systemctl reload nginx"
echo "5. Get SSL certificate: sudo certbot --nginx -d $NEXTCLOUD_DOMAIN"
echo "6. Complete Nextcloud setup via web interface"
echo ""
echo "Database credentials: /root/.nextcloud-db-credentials"
