echo Pi-Hole
curl -sSL https://install.pi-hole.net | sudo bash

echo Replace Bash shell with Dash shell"
sudo dpkg-reconfigure dash
