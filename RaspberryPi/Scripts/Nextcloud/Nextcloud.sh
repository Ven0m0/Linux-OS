#!/usr/bin/env bash
export HOME="/home/${SUDO_USER:-$USER}" LC_ALL=C LANG=C

sudo apt-get update && sudo apt-get upgrade -y

# Install Nginx, MariaDB, PHP-FPM and required PHP modules
sudo apt-get install -y nginx mariadb-server \
  php-fpm php-mysql php-cli php-zip php-xml php-mbstring php-curl php-gd \
  php-bcmath php-gmp php-intl php-imagick php-json php-xmlreader php-xmlwriter \
  php-simplexml zip unzip wget curl openssl redis-server

apt-cache search redis
APCu
intl
imagick

ls /etc/php/*/fpm/php.ini
ls /etc/php/
memory_limit = 512M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 300
cgi.fix_pathinfo = 0
date.timezone = Europe/Berlin

sudo systemctl restart php*-fpm

sudo mysql_secure_installation

sudo mysql -u root -p <<EOF
CREATE DATABASE nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'ncuser'@'localhost' IDENTIFIED BY 'strongpassword';
GRANT ALL ON nextcloud.* TO 'ncuser'@'localhost';
FLUSH PRIVILEGES;
EOF

sudo chown -R www-data:www-data /var/www/nextcloud
sudo chmod -R 755 /var/www/nextcloud

sudo touch /etc/nginx/sites-available/nextcloud.conf

sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d cloud.example.com
sudo certbot renew --dry-run
