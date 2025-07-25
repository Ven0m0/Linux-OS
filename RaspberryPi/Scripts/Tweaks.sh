#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
LC_ALL=C LANG=C
# https://github.com/jmcerrejon/PiKISS/blob/master/res/cRasp.sh

clear

disableSwap() {
    # Disable partition "swap"
    sudo dphys-swapfile swapoff
    sudo dphys-swapfile uninstall
    sudo update-rc.d dphys-swapfile remove
}

read -p "Do you want to disable SWAP? [y/n] " option
case "$option" in
y*) disableSwap ;;
esac

enableZRAM() {
    echo -e "\nEnabling ZRAM...\n"
    cat <<\EOF >/tmp/zram
#!/bin/bash

CORES=$(nproc --all)
modprobe zram num_devices=${CORES}
swapoff -a
SIZE=$(( ($(free | grep -e "^Mem:" | awk '{print $2}') / ${CORES}) * 1024 ))
CORE=0
while [ ${CORE} -lt ${CORES} ]; do
  echo ${SIZE} > /sys/block/zram${CORE}/disksize
  mkswap /dev/zram${CORE} > /dev/null
  swapon -p 5 /dev/zram${CORE}
  (( CORE += 1 ))
done
EOF
    chmod +x /tmp/zram
    sudo mv /tmp/zram /etc/zram
    sudo /etc/zram
    if [ "$(grep -c zram /etc/rc.local)" -eq 0 ]; then
        sudo sed -i 's_^exit 0$_/etc/zram\nexit 0_' /etc/rc.local
    fi
}

echo
read -p "Do you want to enable ZRAM? [y/n] " option
case "$option" in
y*) enableZRAM ;;
esac

https://github.com/salihmarangoz/UbuntuTweaks/blob/22.04/to_be_refactored/Performance.md
$ sudo touch /usr/bin/zram.sh
$ sudo chmod 555 /usr/bin/zram.sh
$ sudo nano /usr/bin/zram.sh
##########################
ZRAM_MEMORY=2048
##########################
set -x
CORES=$(nproc --all)
modprobe zram
ZRAM_DEVICE=
while [ -z "$ZRAM_DEVICE" ] 
do
	ZRAM_DEVICE=$(zramctl --find --size "$ZRAM_MEMORY"M --streams $CORES --algorithm lz4)
	sleep 5
done
mkswap $ZRAM_DEVICE
swapon --priority 5 $ZRAM_DEVICE

# Run on boot
$ sudo crontab -e
# Paste the following lines
@reboot /bin/bash /usr/bin/zram.sh
# Reboot, Check the swap memory
