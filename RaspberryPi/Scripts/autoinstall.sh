sudo micro /etc/apt/apt.conf.d/99local

Binary::apt::DPkg::Progress-Fancy "0";
Binary::apt::APT::Get::Update::InteractiveReleaseInfoChanges "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Update-Package-Lists "0";

# Acquire::Queue-Mode "host";
# Acquire::Queue-Mode "access";
Acquire::CompressionTypes::Order { "lz4"; "zst"; "xz"; "gz"; };


# Make it permanent
echo "kernel.hung_task_timeout_secs = 0" | sudo tee /etc/sysctl.d/99-disable-hung-tasks.conf


# apt-fast
#sudo micro /etc/apt/sources.list.d/apt-fast.list
sudo touch /etc/apt/sources.list.d/apt-fast.list && \
  echo "deb [signed-by=/etc/apt/keyrings/apt-fast.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu focal main" | sudo tee -a /etc/apt/sources.list.d/apt-fast.list

mkdir -p /etc/apt/keyrings
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBC5934FD3DEBD4DAEA544F791E2824A7F22B44BD" | sudo gpg --dearmor -o /etc/apt/keyrings/apt-fast.gpg
sudo apt-get update && sudo apt-get install apt-fast

wget -qO- https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
pi-apps update -y

