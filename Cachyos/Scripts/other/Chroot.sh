#!/usr/bin/env bash
LC_ALL=C
sync; sudo -v

lsblk -A
sudo mount /dev/nvme0n1p2 /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot
#sudo mount /dev/nvme0n1p1 /mnt/boot/efi

sudo mount -t proc proc /mnt/proc
sudo mount --rbind /sys /mnt/sys
sudo mount --rbind /dev /mnt/dev
sudo mount --rbind /run /mnt/run

sudo arch-chroot /mnt /bin/bash

echo "micro /etc/fstab"
echo "micro /etc/mkinitcpio.conf"


sudo mkinitcpio -P
exit
sudo umount -R /mnt/run
sudo umount -R /mnt/dev
sudo umount -R /mnt/sys
sudo umount -R /mnt/proc
sudo umount /mnt/boot/efi
# sudo umount /mnt/boot 
umount /mnt

sudo reboot



# sudo mkinitcpio -P
