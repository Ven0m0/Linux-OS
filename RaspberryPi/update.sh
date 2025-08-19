#!/usr/bin/env bash
export LC_ALL=C LANG=C
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR
#──────────── Helpers ────────────────────
has() { command -v "$1" &>/dev/null; }
p() { printf "%s\n" "$@"; }
#─────────────────────────────────────────
sync; sudo -v
if command -v nala &>/dev/null; then
  sudo nala fetch -y
  sudo nala update -y
  sudo nala upgrade -y
  sudo nala clean -y
  sudo nala autoclean -y
  sudo nala autoremove -y
elif command -v apt-fast &>/dev/null; then
  sudo apt-fast update -y
  sudo apt-fast upgrade -y
  sudo apt-fast dist-upgrade -y
  sudo apt-fast full-upgrade -y
  sudo apt-fast autoremove
else
  sudo apt-get update -y
  sudo apt-get upgrade -y
  sudo apt-get dist-upgrade -y 
  sudo apt full-upgrade -y
fi
# Check's the broken packages and fix them
sudo dpkg --configure -a
if [ $? -ne 0 ]; then
    p "There were issues configuring packages."
else
    p "No broken packages found or fixed successfully."
fi

if [ "$(type -t G_SUDO 2>/dev/null)" = function ]; then
    G_SUDO /boot/dietpi/dietpi-update 1
else
    sudo /boot/dietpi/dietpi-update
fi
sudo dietpi-update || sudo bash -c "dietpi-update"

if has pihole; then
    sudo pihole -up
else
    p "Pi-hole is NOT installed"
fi

has rpi-eeprom-update && sudo rpi-eeprom-update -a
has rpi-update && sudo PRUNE_MODULES=1 rpi-update
#sudo JUST_CHECK=1 rpi-update
# sudo PRUNE_MODULES=1 rpi-update
