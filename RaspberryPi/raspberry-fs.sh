#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C

#---------------------------------------
# Modern Raspbian/DietPi F2FS Flash Script
# With tmpfs acceleration and first-boot resize
#---------------------------------------

usage() {
    cat <<EOF
Usage: $0 [-i image] [-d device] [-u username] [-p password] [-s] [-h]

Options:
  -i IMAGE      Source Raspberry Pi OS/DietPi image (.img or .img.xz) or URL
  -d DEVICE     Target block device (SD card, USB drive)
  -u USERNAME   Optional: create a user
  -p PASSWORD   Optional: password for the new user (SHA512)
  -s            Optional: enable SSH
  -h            Show this help
EOF
    exit 1
}

#---------------------------------------
# Root check
#---------------------------------------
if [[ $(id -u) -ne 0 ]]; then
    echo "This script must be run as root."
    exec sudo bash "$0" "$@"
fi

#---------------------------------------
# Parse arguments
#---------------------------------------
IMAGE=""
DEVICE=""
USERNAME=""
PASSWORD=""
ENABLE_SSH=0

while getopts "i:d:u:p:sh" opt; do
    case $opt in
        i) IMAGE="$OPTARG" ;;
        d) DEVICE="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        s) ENABLE_SSH=1 ;;
        h|*) usage ;;
    esac
done

[[ -n "$IMAGE" && -n "$DEVICE" ]] || usage
[[ -b "$DEVICE" ]] || { echo "Target device $DEVICE does not exist."; exit 1; }

#---------------------------------------
# Setup working directories
#---------------------------------------
WORKDIR=$(mktemp -d)
SRC_IMG="$WORKDIR/source.img"
BOOT_MNT="$WORKDIR/boot"
ROOT_MNT="$WORKDIR/root"

mkdir -p "$BOOT_MNT" "$ROOT_MNT"

#---------------------------------------
# Download or extract image
#---------------------------------------
echo "[*] Preparing source image..."
if [[ "$IMAGE" =~ ^https?:// ]]; then
    echo "[*] Downloading $IMAGE ..."
    wget -q --show-progress -O "$WORKDIR/$(basename "$IMAGE")" "$IMAGE"
    IMAGE="$WORKDIR/$(basename "$IMAGE")"
fi

if [[ "$IMAGE" =~ \.xz$ ]]; then
    echo "[*] Extracting $IMAGE ..."
    xz -dc "$IMAGE" > "$SRC_IMG"
else
    cp "$IMAGE" "$SRC_IMG"
fi

#---------------------------------------
# Partition and format target device
#---------------------------------------
echo "[*] WARNING: All data on $DEVICE will be destroyed!"
read -p "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo "[*] Wiping existing partitions..."
wipefs -af "$DEVICE"
parted -s "$DEVICE" mklabel msdos
parted -s "$DEVICE" mkpart primary fat32 0% 512MB
parted -s "$DEVICE" mkpart primary 512MB 100%
partprobe "$DEVICE"

if [[ "$DEVICE" =~ mmcblk ]]; then
    PART_BOOT="${DEVICE}p1"
    PART_ROOT="${DEVICE}p2"
else
    PART_BOOT="${DEVICE}1"
    PART_ROOT="${DEVICE}2"
fi

echo "[*] Formatting partitions..."
mkfs.vfat -F32 -n boot "$PART_BOOT"

# Hot/cold files for f2fs
HOT='db,sqlite,tmp,log,json,conf,journal,pid,lock,xml,ini,py'
TXT='pdf,txt,sh,ttf,otf,woff,woff2'
IMG='jpg,jpeg,png,webp,avif,jxl,gif,svg'
MED='mkv,mp4,mov,avi,webm,mpeg,mp3,ogg,opus,wav'
ZIP='img,iso,gz,tar,zip,deb'
COLD="${TXT},${IMG},${MED},${ZIP}"

mkfs.f2fs -f -S -i \
  -O extra_attr,inode_checksum,sb_checksum,compression,flexible_inline_xattr \
  -E "$HOT" -e "$COLD" -l root "$PART_ROOT"

#---------------------------------------
# Mount source image partitions
#---------------------------------------
echo "[*] Mounting source image..."
LOOP_DEV=$(losetup --show -fP "$SRC_IMG")
mount "${LOOP_DEV}p1" "$BOOT_MNT"
mount "${LOOP_DEV}p2" "$ROOT_MNT"

#---------------------------------------
# Mount target partitions
#---------------------------------------
TARGET_BOOT="$WORKDIR/target_boot"
TARGET_ROOT="$WORKDIR/target_root"
mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
mount "$PART_BOOT" "$TARGET_BOOT"
mount "$PART_ROOT" "$TARGET_ROOT"

#---------------------------------------
# Tmpfs acceleration for root copy
#---------------------------------------
echo "[*] Copying root filesystem via tmpfs..."
ROOT_SIZE_MB=$(du -sm "$ROOT_MNT" | awk '{print $1}')
TMPFS_SIZE=$((ROOT_SIZE_MB + 512))  # add buffer
TMPFS_MNT="$WORKDIR/tmpfs_root"

mkdir -p "$TMPFS_MNT"
mount -t tmpfs -o size=${TMPFS_SIZE}M tmpfs "$TMPFS_MNT"

echo "[*] rsync from image to tmpfs..."
rsync -aHAX "$ROOT_MNT/" "$TMPFS_MNT/"

echo "[*] rsync from tmpfs to target root partition..."
rsync -aHAX --progress "$TMPFS_MNT/" "$TARGET_ROOT/"

umount "$TMPFS_MNT"
rm -rf "$TMPFS_MNT"

#---------------------------------------
# Copy boot partition
#---------------------------------------
echo "[*] Copying boot partition..."
rsync -aHAX "$BOOT_MNT/" "$TARGET_BOOT/"

#---------------------------------------
# Update bootloader and fstab for F2FS
#---------------------------------------
BOOT_UUID=$(blkid -s PARTUUID -o value "$PART_BOOT")
ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT")

sed -i "s|root=[^ ]*|root=PARTUUID=$ROOT_UUID|" "$TARGET_BOOT/cmdline.txt"
sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "$TARGET_BOOT/cmdline.txt"

cat > "$TARGET_ROOT/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$BOOT_UUID  /boot   vfat    defaults                    0   2
PARTUUID=$ROOT_UUID  /       f2fs    defaults,noatime,discard    0   1
EOF

#---------------------------------------
# Optional SSH and user setup
#---------------------------------------
if [[ $ENABLE_SSH -eq 1 ]]; then
    touch "$TARGET_ROOT/boot/ssh"
fi

if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
    HASHED_PASS=$(echo "$PASSWORD" | openssl passwd -6 -stdin)
    chroot "$TARGET_ROOT" /usr/sbin/useradd -m -s /bin/bash "$USERNAME"
    echo "$USERNAME:$HASHED_PASS" | chroot "$TARGET_ROOT" /usr/sbin/chpasswd -e
fi

#---------------------------------------
# First-boot F2FS resize script
#---------------------------------------
echo "[*] Creating first-boot F2FS resize script..."
mkdir -p "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount"
cat > "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount/f2fsresize" <<'EOF'
#!/bin/sh
# Initramfs script to expand F2FS root filesystem on first boot
. /scripts/functions

log_begin_msg "Expanding F2FS root filesystem..."
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -x /sbin/resize.f2fs ]; then
    /sbin/resize.f2fs "$ROOT_DEV"
    log_end_msg "F2FS root filesystem expanded."
    rm -f /etc/initramfs-tools/scripts/init-premount/f2fsresize
else
    log_end_msg "resize.f2fs not found. Skipping."
fi
EOF

chmod +x "$TARGET_ROOT/etc/initramfs-tools/scripts/init-premount/f2fsresize"

#---------------------------------------
# Cleanup
#---------------------------------------
echo "[*] Syncing and unmounting..."
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT"
losetup -d "$LOOP_DEV"
rm -rf "$WORKDIR"

echo "[+] Done! Your F2FS Raspberry Pi image is ready on $DEVICE."
echo "[+] First boot will automatically expand the root filesystem."
