echo "Install Pi-Hole"
curl -sSL https://install.pi-hole.net | sudo bash

echo "Install PiKISS <3"
curl -sSL https://git.io/JfAPE | bash

echo "Replace Bash shell with Dash shell"
sudo dpkg-reconfigure dash


# App Store for FOSS Projects 
#echo "Install Pi-Apps"
#echo "#https://github.com/Botspot/pi-apps"
#wget -qO- https://raw.githubusercontent.com/Botspot/pi-apps/master/install | bash

echo "Install PiApps-terminal_bash-edition"
echo "https://github.com/Itai-Nelken/PiApps-terminal_bash-edition"
wget -qO- https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
pi-apps update -y

echo 
echo "https://github.com/Drewsif/PiShrink"
sudo apt update && sudo apt install -y wget parted gzip pigz xz-utils udev e2fsprogs
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo mv pishrink.sh /usr/local/bin
