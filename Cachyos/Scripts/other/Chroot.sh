#!/usr/bin/env bash
LC_ALL=C
sync; sudo -v

lsblk -A
sudo mount /dev/nvme0n1p2 /mnt
sudo mount --bind /dev /mnt/dev 
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo mount --bind /run /mnt/run

sudo chroot /mnt

micro /etc/fstab

exit
sudo umount /mnt/run
sudo umount /mnt/sys
sudo umount /mnt/proc
sudo umount /mnt/dev
sudo umount /mnt

sudo reboot



# mkinitcpio -P
