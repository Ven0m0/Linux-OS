echo "Install Pi-Hole"
curl -sSL https://install.pi-hole.net | sudo bash

echo "Install PiKISS <3"
curl -sSL https://git.io/JfAPE | bash

echo "Replace Bash shell with Dash shell"
sudo dpkg-reconfigure dash
