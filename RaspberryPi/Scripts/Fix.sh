sudo apt-get install ntpdate
sudo ntpdate -u ntp.ubuntu.com
sudo apt-get install ca-certificates

# SSH fix
find -O3 ~/.ssh/ -type f -exec chmod 600 {}
find -O3 ~/.ssh/ -type d -exec chmod 700 {}
find -O3 ~/.ssh/ -type f -name "*.pub" -exec chmod 644 {}
sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg

# Nextcloud CasaOS fix
sudo docker exec nextcloud ls -ld /tmp
sudo docker exec nextcloud chown -R www-data:www-data /tmp
sudo docker exec nextcloud chmod -R 755 /tmp
sudo docker exec nextcloud ls -ld /tmp
