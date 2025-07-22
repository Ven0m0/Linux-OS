echo "Install Pi-Hole"
curl -sSL https://install.pi-hole.net | sudo bash

echo "Install PiKISS <3"
curl -sSL https://git.io/JfAPE | bash

echo "Replace Bash shell with Dash shell"
sudo dpkg-reconfigure dash

#https://github.com/Botspot/pi-apps
# App Store for FOSS Projects 
#echo "Install Pi-Apps"
#wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash

echo "Install PiApps-terminal_bash-edition"
wget -qO- https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
pi-apps update -y
