#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C SHELL="${BASH:-$(command -v bash)}" HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sync; sudo -v

# Raspbian-F2FS v207
# Original Script: https://github.com/d-a-v/raspbian-f2fs
# Complete re-write by Timothy Brown - August 2018.
#
# This script operates in two modes:
# 1. Device Target Mode: In this mode the script will format an SD card or
# USB flash drive as F2FS (Flash Friendly Filesystem) and copy a fully bootable
# installation of Raspbian onto it.
#
# 2. Image Target Mode: This mode takes a fresh image of Raspbian and converts
# the root partition from EXT4 to F2FS. The resulting image can be written to an
# SD card or USB flash device just like the original image. These images will
# automatically expand to fit the media on first boot.
#
# Both modes require an untouched zip or img file of Raspbian or Raspbian Lite,
# which can be downloaded from www.raspberrypi.org.
#
# This script has only been tested *running on* Raspbian Stretch, other distros
# *may* work if the proper packages are installed (f2fs-tools, pv) or tweaks to
# the script are made.
#
# Syntax: raspbian-f2fs source.zip|img /dev/target|target.img

cmdname="$(basename $0)"
filename="$1"
targetdev=""
targetboot=/mnt/target_boot
targetroot=/mnt/target_root
sourcedev=$(losetup -f)
sourceboot=/mnt/source_boot
sourceroot=/mnt/source_root

raspimgver="2018-06-27"
scriptver="v207"

set -e

# Print header.
echo "                                                                               "
echo "Raspbian F2FS SD/Flash Drive Creation Tool $scriptver"
echo "-------------------------------------------------------------------------------"
echo "                                                                               "

# Make sure both command line arguments are provided.
if [ -z "$1" ] || [ -z "$2" ]; then
	echo "Syntax: $cmdname source.zip|img /dev/target|target.img"
	echo "[Source] A zip file or image of Raspbian."
	echo "[Target] The device to flash or new image file to create."
	echo "                                                                               "
	echo "Example: $cmdname /mnt/usb/2018-06-27-raspbian.img /dev/sdb"
	echo "This will generate a bootable F2FS version of Raspbian from an image file"
	echo "and flash it onto an externally attached SD card."
	exit 1
fi

# Make sure we're running as root.
if [ ! "$(whoami)" = "root" ]; then
	echo "Error: This script *must* be run as root!"
	echo "       Please use 'sudo su -' and then re-run this script."
	exit 1
fi

# Verify script compatibility.
echo "${cmdname}: Verifying source image compatibility."
case "$(basename ${filename%%.*})" in
	*${raspimgver}*)
	echo "Source Image = $(basename ${filename%%.*})"
	;;
	*)
	echo "******************* WARNING *******************"
	echo "Source Image: $(basename ${filename%%.*})"
	echo "This version of Raspbian has not been tested   "
	echo "with this script. Proceede at your own risk.   "
	echo "This is not a joke. Must bring your own weapons."
	echo "************ SAFETY NOT GUARANTEED ************"
	echo "                                               "
	sleep 5
	;;
esac

# Make sure required software is installed.
#if [ "$(dpkg-query -W -f='${Status}' pv 2>/dev/null | grep -c "ok installed")" == "0" ]; then
#	echo "${cmdname}: Installing required package [pv]."
#	apt-get -qq install pv
#fi
#if [ "$(dpkg-query -W -f='${Status}' f2fs-tools 2>/dev/null | grep -c "ok installed")" == "0" ]; then
#	echo "${cmdname}: Installing required package [f2fs-tools]."
#	apt-get -qq install f2fs-tools
#fi

# Check to see if our source is a zip file or image.
if [ "${filename#*.}" = "zip" ]; then
	imgsrc="${filename%%.*}.img"
	echo "${cmdname}: Source appears to be a zip file."
	echo "Unzipping $filename -> $imgsrc."
	test -r "$imgsrc" || unzip -p "$filename" > "$imgsrc"
elif [ "${filename#*.}" = "img" ]; then
	imgsrc="$filename"
	echo "${cmdname}: Source appears to be an image."
fi

# Check to see if our target is a device or image.
echo "${cmdname}: Verifying target."
if [ -b "$2" ]; then
	targetdev="$2"
	targetimg=""
	case "$targetdev" in
		"/dev/mmcblk"*)
		echo "[Block Device] Internal SD Card"
		target_p1="p1"
		target_p2="p2"
		;;
		"/dev/sd"*)
		echo "[Block Device] External USB Flash/SD Card"
		target_p1="1"
		target_p2="2"
		;;
	esac
	echo "********** THIS DEVICE WILL BE WIPED **********"
	parted -s "$targetdev" print || true
	echo "**********    Are you sure? (yes)    **********"
	read ans
	test $ans = "yes" || exit 1
elif [ ! -e "$2" ]; then
	echo "[Loop Device] Internal Disk Image"
	targetdev=""
	targetimg="$2"
	target_p1="p1"
	target_p2="p2"
else
	echo "Target ($2) does not appear to be a valid device or the disk image already exists."
	echo "Aborting."
	exit 1
fi

# Verify nothing is currently mounted.
echo "${cmdname}: Making sure source and target aren't mounted."
if [ -b "$sourcedev" ]; then
	umount ${sourcedev}* 2> /dev/null || true
fi
if [ -b "$targetdev" ]; then
	umount ${targetdev}* 2> /dev/null || true
fi
losetup -d $(losetup -O NAME -n -j "$imgsrc") 2> /dev/null || true
losetup -d $(losetup -O NAME -n -j "$targetimg") 2> /dev/null || true

# Setup source and target mount points.
echo "${cmdname}: Setting up mount points."
test -r /mnt || mkdir -p /mnt
test -r "$sourceboot" || mkdir -p "$sourceboot"
test -r "$sourceroot" || mkdir -p "$sourceroot"
test -r "$targetboot" || mkdir -p "$targetboot"
test -r "$targetroot" || mkdir -p "$targetroot"

# If our target is an image, create it now.
if [ ! -z "$targetimg" ]; then
	echo "${cmdname}: Creating blank disk image."
	let targetimgsize=$(du --block-size=M $imgsrc | cut -d "M" -f1)+200
	truncate -s ${targetimgsize}M "$targetimg"
	echo "${cmdname}: Attaching target disk image."
	targetdev=$(losetup --show -f -P "$targetimg")
fi

# Mount source image.
echo "${cmdname}: Attaching source disk image."
sourcedev=$(losetup --show -f -P "$imgsrc")
echo "${cmdname}: Mounting source boot partition."
mount -o ro ${sourcedev}p1 $sourceboot
echo "${cmdname}: Mounting source root partition."
mount -o ro ${sourcedev}p2 $sourceroot

#######################################
# Write out partition table.

# Wipe exsisting partition data from target.
echo "${cmdname}: Erasing current partition table on target."
wipefs -aq $targetdev
# Generate new MBR style partition table and two partitions:
# P1 = 64MiB FAT32 LBA with 8192 sector offset.
# P2 = Remaining Space Linux filesystem directly after the first partition.
echo "${cmdname}: Creating new partition table on target."
#parted -s $targetdev mklabel msdos mkpart primary fat32 8192s 64MiB mkpart primary ext2 64MiB 100%
parted -s $targetdev mklabel msdos mkpart primary fat32 8192s 256MiB mkpart primary ext2 256MiB 100%
# Reload the partition table.
partprobe $targetdev
# Print the new partition table.
parted -s $targetdev print
# Read the new partition UUIDs.
bootuuid=$(blkid -o value -s PARTUUID ${targetdev}$target_p1)
rootuuid=$(blkid -o value -s PARTUUID ${targetdev}$target_p2)

#######################################
# Now dealing with partition 1.

# Format target partition 1 as FAT32.
echo "${cmdname}: Formatting boot partition on target as FAT32."
mkfs.fat -n boot ${targetdev}$target_p1
# Mount target parition 1.
echo "${cmdname}: Mounting target boot partition."
mount ${targetdev}$target_p1 $targetboot
# Count files.
echo "${cmdname}: Getting file count on source."
numfiles=$(find $sourceboot/ -type f -printf . | wc -c)
# Copy boot files from source to target.
echo "${cmdname}: Copying $numfiles files from source image to target device."
rsync -axi $sourceboot/ $targetboot/ | pv -leps $numfiles >/dev/null
# Update cmdline.txt on the target.
echo "${cmdname}: Updating cmdline.txt options."
cp $targetboot/cmdline.txt $targetboot/cmdline.old
sed -i 's/rootfstype=[^ ]*/rootfstype=f2fs/g' $targetboot/cmdline.txt
sed -i 's/root=[^ ]*/root=PARTUUID='"$rootuuid"'/g' $targetboot/cmdline.txt
## If target is a device then stop the partition resize script from running on boot.
if [ -z "$targetimg" ]; then
	sed -i 's| init=/usr/lib/raspi-config/init_resize.sh||' $targetboot/cmdline.txt
	if ! grep -q splash "$targetboot/cmdline.txt"; then
		sed -i 's/ quiet//g' $targetboot/cmdline.txt
	fi
fi

# Sync
echo "${cmdname}: Done processing the boot partition!"
echo "${cmdname}: Syncing..."
sync

#######################################
# Now dealing with partition 2.

# Format target parition 2 as F2FS.
echo "${cmdname}: Formatting root partition on target as F2FS."
mkfs.f2fs -o 20 -O extra_attr,inode_checksum,sb_checksum,compression -l root ${targetdev}$target_p2
# Mount target partition 2.
echo "${cmdname}: Mounting target root partition."
mount ${targetdev}$target_p2 $targetroot
# Count files.
echo "${cmdname}: Getting file count on source image."
numfiles=$(df -i $sourceroot/ | perl -ane 'print $F[2] if $F[5] =~ m:^/:')
# Copy root files from source to target.
echo "${cmdname}: Copying $numfiles files from source image to target device."
rsync -axi $sourceroot/ $targetroot/ | pv -leps $numfiles >/dev/null
# Update fstab on the target.
echo "${cmdname}: Generating new fstab on target."
mv $targetroot/etc/fstab $targetroot/etc/fstab.old
cat > $targetroot/etc/fstab << EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$bootuuid  /boot   vfat    defaults                    0   2
PARTUUID=$rootuuid  /       f2fs    defaults,noatime,discard    0   1
EOF

# If the target is an image, create scripts to resize the filesystem at boot.
if [ ! -z "$targetimg" ]; then
	echo "${cmdname}: Setting up F2FS filesystem expansion."
	# Initramfs: F2FS Resize Hook Script
	cat > "${targetroot}/etc/initramfs-tools/hooks/f2fsresize" << EOF
#!/bin/sh
# F2FS Resize Hook Script


PREREQ=""
prereqs()
{
	echo "\$PREREQ"
}


case \$1 in
prereqs)
	prereqs
	exit 0
	;;
esac


. /usr/share/initramfs-tools/hook-functions
# Begin real processing below this line
if [ ! -x "/sbin/resize.f2fs" ]; then
	exit 0
fi


copy_exec /sbin/resize.f2fs
exit 0
EOF
	chmod +x "${targetroot}/etc/initramfs-tools/hooks/f2fsresize"

	# Initramfs: F2FS Resize Boot Script
	cat > "${targetroot}/etc/initramfs-tools/scripts/init-premount/f2fsresize" << EOF
#!/bin/sh
# F2FS Resize

PREREQ=""
prereqs()
{
	echo "\$PREREQ"
}

case \$1 in
prereqs)
	prereqs
	exit 0
	;;
esac

. /scripts/functions
# Begin real processing below this line
if [ ! -x "/sbin/resize.f2fs" ]; then
	panic "Resize.F2FS Executable Not Found"
fi

log_begin_msg "Expanding F2FS Filesystem"
/sbin/resize.f2fs "/dev/disk/by-partuuid/$rootuuid" || panic "F2FS Resize Failed"
log_end_msg

exit 0
EOF
	chmod +x "${targetroot}/etc/initramfs-tools/scripts/init-premount/f2fsresize"

	# Cleanup Script
	cat > "${targetroot}/etc/f2fsresize_cleanup" << EOF
#!/bin/bash
printf "Successfully expanded F2FS volume!"
sed -i '/\/bin\/bash \/etc\/f2fsresize_cleanup/d' /etc/rc.local
sed -i '/initramfs initrd.img followkernel/d' /boot/config.txt
mv /usr/lib/raspi-config/init_resize.old /usr/lib/raspi-config/init_resize.sh
rm /boot/initrd.img
rm /etc/initramfs-tools/scripts/init-premount/f2fsresize
rm /etc/initramfs-tools/hooks/f2fsresize
rm /etc/f2fsresize_cleanup
EOF
	chmod +x "${targetroot}/etc/f2fsresize_cleanup"

	# Get kernel version.
	kernelver=$(ls ${targetroot}/lib/modules/ | grep "v7+" | head -n 1)

	# Modify the init_resize script to start our custom initramfs after expanding the partition.
	test -r $targetroot/usr/lib/raspi-config/init_resize.sh && cp $targetroot/usr/lib/raspi-config/init_resize.sh $targetroot/usr/lib/raspi-config/init_resize.old
	let linenum=$(grep -n "mount / -o remount,rw"  "$targetroot/usr/lib/raspi-config/init_resize.sh" | head -n 1 | cut -d: -f1)+2
	sed -i ''"$linenum"'i echo "initramfs initrd.img followkernel" >> /boot/config.txt' "$targetroot/usr/lib/raspi-config/init_resize.sh"
	sed -i ''"$linenum"'i sed -i \x27\x27"$(grep -n "exit 0"  "/etc/rc.local" | tail -n 1 | cut -d: -f1)"\x27i /bin/bash /etc/f2fsresize_cleanup\x27 /etc/rc.local' "$targetroot/usr/lib/raspi-config/init_resize.sh"
fi

echo "${cmdname}: Syncing..."
sync

#######################################
# Now chrooting into the target rootfs.

# Bind some host filesystems to target for chroot.
echo "${cmdname}: Building up chroot enviroment on target rootfs."
for i in dev proc sys dev/pts; do
	mount --bind /$i $targetroot/$i
done
mount --bind $targetboot $targetroot/boot

# Chroot into target and perform the following actions:
# 1) Disable resize2fs_once script.
# 2) Install f2fs-tools.
# If the target is an image, additionally perform these actions:
# 3) Generate initramfs for F2FS filesystem expansion.
cat << EOF | chroot $targetroot env -i \
LANG=en_GB.utf8 LANGUAGE=en_GB.utf8 LC_ALL=en_GB.utf8 TERM=$TERM HOME=/root /bin/bash --login
echo "${cmdname}@${targetroot}: Stopping automatic ext4 filesystem expansion."
update-rc.d resize2fs_once remove
test -r /etc/init.d/resize2fs_once && rm /etc/init.d/resize2fs_once
echo "${cmdname}@${targetroot}: Installing f2fs-tools."
apt-get -qq install f2fs-tools
apt-get -qq clean
test -z "$targetimg" || echo "${cmdname}@${targetroot}: Generating initramfs for F2FS filesystem expansion."
test -z "$targetimg" || mkinitramfs -o /boot/initrd.img $kernelver
exit 0
EOF

# Unbind host filesystems from target.
echo "${cmdname}: Tearing down chroot enviroment."
sync
sleep 1
for i in boot dev/pts sys proc dev; do
	umount $targetroot/$i
done

# Sync.
echo "${cmdname}: Done processing the root partition!"
echo "${cmdname}: Syncing..."
sync

# Print info on the new device.
echo "${cmdname}: Successfully completed Raspbian F2FS installation!"
echo "************************************************************"
df -hT --total ${targetdev}$target_p1 ${targetdev}$target_p2
echo "************************************************************"

echo "${cmdname}: Unmounting everything."
umount $sourceboot 2> /dev/null || true
umount $sourceroot 2> /dev/null || true
umount $targetboot 2> /dev/null || true
umount $targetroot 2> /dev/null || true
umount ${sourcedev}* 2> /dev/null || true
umount ${targetdev}* 2> /dev/null || true
losetup -d $sourcedev 2> /dev/null || true
losetup -d $targetdev 2> /dev/null || true

# Cleanup.
echo "${cmdname}: Cleaning up."
test -r "$sourceboot" && rm -rf $sourceboot
test -r "$sourceroot" && rm -rf $sourceroot
test -r "$targetboot" && rm -rf $targetboot
test -r "$targetroot" && rm -rf $targetroot

# Print footer.
echo "                                                                               "
echo "-------------------------------------------------------------------------------"
#######################################
