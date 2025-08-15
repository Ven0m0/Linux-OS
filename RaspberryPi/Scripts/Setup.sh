echo "Install Pi-Hole"
curl -sSL https://install.pi-hole.net | sudo bash

echo "Install PiKISS <3"
curl -sSL https://git.io/JfAPE | bash

echo Alternative install
git clone https://github.com/jmcerrejon/PiKISS.git && cd PiKISS
./piKiss.sh

git config --global http.sslVerify false
git pull

echo "Replace Bash shell with Dash shell"
sudo dpkg-reconfigure dash

echo "Install PiApps-terminal_bash-edition"
echo "https://github.com/Itai-Nelken/PiApps-terminal_bash-edition"
wget -qO- https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
pi-apps update -y

echo "Install nala"
sudo apt install nala

echo 'APT::Acquire::Retries "5";
Acquire::Queue-Mode "access";
Acquire::Languages "none";
APT::Acquire::ForceIPv4 "true";
APT::Get::AllowUnauthenticated "true";
Acquire::CompressionTypes::Order:: "gz";
APT::Acquire::Max-Parallel-Downloads "5";' | sudo tee /etc/apt/apt.conf.d/99parallel


sudo netselect-apt stable && sudo mv sources.list /etc/apt/sources.list && sudo apt update

sudo sh -c 'echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io'


# apt-fast
#sudo micro /etc/apt/sources.list.d/apt-fast.list
sudo touch /etc/apt/sources.list.d/apt-fast.list && \
  echo "deb [signed-by=/etc/apt/keyrings/apt-fast.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu focal main" | sudo tee -a /etc/apt/sources.list.d/apt-fast.list

mkdir -p /etc/apt/keyrings
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBC5934FD3DEBD4DAEA544F791E2824A7F22B44BD" | sudo gpg --dearmor -o /etc/apt/keyrings/apt-fast.gpg
sudo apt-get update && sudo apt-get install apt-fast

# Deb-get
sudo apt install curl lsb-release wget
curl -sL https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get | sudo -E bash -s install deb-get

# Eget
curl -s https://zyedidia.github.io/eget.sh | sh
cp -v eget $HOME/.local/bin/eget

# Pacstall
sudo apt install pacstall
sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install || wget -q https://pacstall.dev/q/install -O -)"

## Fix timeout for tty
# Apply immediately
sudo sysctl -w kernel.hung_task_timeout_secs=0
echo 0 | sudo tee /proc/sys/kernel/hung_task_timeout_secs

# Make it permanent
echo "kernel.hung_task_timeout_secs = 0" | sudo tee /etc/sysctl.d/99-disable-hung-tasks.conf

# Reload configs so it's applied now (and on boot)
sudo sysctl --system


python3 -m pip install --upgrade pip
pip cache purge
sudo apt remove lib*-doc
flatpak uninstall --unused --delete-data
docker system prune --all --volumes
sudo apt remove texlive-*-doc
sudo apt-get --purge remove tex.\*-doc$

sudo apt install --fix-missings
sudo apt install --fix-broken
pip install --upgrade pip

# YT-DLP
sudo add-apt-repository ppa:tomtomtom/yt-dlp    # Add ppa repo to apt
sudo apt update                                 # Update package list
sudo apt install yt-dlp                         # Install yt-dlp

# DISABLE THESE SERVICES ON OLD SYSTEMS
sudo apt remove whoopsie # Error Repoting
sudo systemctl mask packagekit.service # gnome-software
sudo systemctl mask geoclue.service # CAUTION: Disable if you don't use Night Light or location services
sudo apt remove gnome-online-accounts # Gnome online accounts plugins

APPS=(
btrfs-progs
)
sudo apt install $APPS
