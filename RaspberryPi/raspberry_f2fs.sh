#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C

#---------------------------------------
# Modern Raspbian/DietPi F2FS Flash Script
# Supports: Image URL/.xz, SD card or USB, F2FS root, optional SSH & user
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
mkfs.f2fs -f -O extra_attr,compression -l root "$PART_ROOT"

#---------------------------------------
# Mount image partitions
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
# Copy boot and root partitions
#---------------------------------------
echo "[*] Copying boot files..."
rsync -aHAX "$BOOT_MNT/" "$TARGET_BOOT/"

echo "[*] Copying root filesystem..."
rsync -aHAX "$ROOT_MNT/" "$TARGET_ROOT/"

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
# Cleanup
#---------------------------------------
echo "[*] Syncing and unmounting..."
sync
umount "$BOOT_MNT" "$ROOT_MNT" "$TARGET_BOOT" "$TARGET_ROOT"
losetup -d "$LOOP_DEV"
rm -rf "$WORKDIR"

echo "[+] Done! Your F2FS Raspberry Pi image is ready on $DEVICE."
