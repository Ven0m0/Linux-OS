#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C SHELL="${BASH:-$(command -v bash)}" HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sync; sudo -v

usage()
{
  cat <<EOF
Usage: $(basename "$0") [options] [source.img|source.zip] [ /dev/target | target.img ]
Options:
  -s SIZE_MB   : fat32 partition size in MiB (minimum 1024). Default 1024.
  -I           : interactively select source image with fzf
  -D           : interactively select target device with fzf
  -h           : this help
Examples:
  $(basename "$0") -s 2048 raspbian.img /dev/sdb
  $(basename "$0") -I -D
EOF
}

# defaults
FAT_MB=1024
SELECT_IMAGE=0
SELECT_DEVICE=0

while getopts "s:IDh" opt; do
  case "$opt" in
    s) FAT_MB=$OPTARG;;
    I) SELECT_IMAGE=1;;
    D) SELECT_DEVICE=1;;
    h) usage; exit 0;;
    *) usage; exit 1;;
  esac
done
shift $((OPTIND-1))

# enforce minimum
if [ "$FAT_MB" -lt 1024 ]; then
  FAT_MB=1024
fi

# helpers
pick_image()
{
  # find common image types and let fzf pick one
  IFS=$'\n' read -r -d '' -a files < <(find . -maxdepth 3 -type f \( -iname '*.img' -o -iname '*.zip' \) -print 2>/dev/null; printf '\0')
  if [ "${#files[@]}" -eq 0 ]; then
    echo "No .img or .zip files found under $(pwd)" >&2
    return 1
  fi
  printf '%s\n' "${files[@]}" | fzf --height 40% --border --preview 'ls -lh {} 2>/dev/null' --prompt='Select image> ' | sed -n '1p'
}

pick_device()
{
  # list sd* and mmcblk* disks (including removable)
  lsblk -dpno NAME,MODEL,SIZE 2>/dev/null | grep -E '/dev/(sd|mmcblk)' | awk '{$1=$1; print}' |
    fzf --height 40% --border --preview 'lsblk -no NAME,MODEL,SIZE,RM,ROTA {} 2>/dev/null' --prompt='Select target device> ' |
    awk '{print $1}' | sed -n '1p'
}

# resolve source (interactive or positional)
if [ "$SELECT_IMAGE" -eq 1 ]; then
  filename="$(pick_image)" || exit 1
elif [ $# -ge 1 ]; then
  filename="$1"
  shift 1
else
  echo "No source provided. Use -I to select interactively or pass source as first arg." >&2
  usage
  exit 1
fi

# resolve target (interactive or positional)
if [ "$SELECT_DEVICE" -eq 1 ]; then
  targetarg="$(pick_device)" || exit 1
elif [ $# -ge 1 ]; then
  targetarg="$1"
  shift 1
else
  echo "No target provided. Use -D to select interactively or pass target as second arg." >&2
  usage
  exit 1
fi

cmdname="$(basename "$0")"
filename="${filename}"
targetarg="${targetarg}"
targetdev=""
targetimg=""
target_p1=""
target_p2=""
targetboot=/mnt/target_boot
targetroot=/mnt/target_root
sourcedev=$(losetup -f)
sourceboot=/mnt/source_boot
sourceroot=/mnt/source_root

raspimgver="2018-06-27"
scriptver="v207"

# root check
if [ "$(whoami)" != "root" ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# verify source type
if [ "${filename##*.}" = "zip" ]; then
  imgsrc="${filename%.*}.img"
  test -r "$imgsrc" || unzip -p "$filename" > "$imgsrc"
elif [ "${filename##*.}" = "img" ]; then
  imgsrc="$filename"
else
  echo "Source must be .img or .zip" >&2
  exit 1
fi

# verify target
if [ -b "$targetarg" ]; then
  targetdev="$targetarg"
  targetimg=""
  case "$targetdev" in
    /dev/mmcblk*)
      target_p1="p1"
      target_p2="p2"
      ;;
    /dev/sd*)
      target_p1="1"
      target_p2="2"
      ;;
    *)
      # fallback: default numeric suffix
      target_p1="1"
      target_p2="2"
      ;;
  esac
  echo "********** THIS DEVICE WILL BE WIPED **********"
  parted -s "$targetdev" print || true
  echo "********** Are you sure? (yes) **********"
  read -r ans
  [ "$ans" = "yes" ] || exit 1
elif [ ! -e "$targetarg" ]; then
  # create image file
  targetdev=""
  targetimg="$targetarg"
  target_p1="p1"
  target_p2="p2"
else
  echo "Target ($targetarg) invalid." >&2
  exit 1
fi

# unmount leftovers
if [ -b "$sourcedev" ]; then
  umount "${sourcedev}"* 2>/dev/null || true
fi
if [ -b "$targetdev" ]; then
  umount "${targetdev}"* 2>/dev/null || true
fi
losetup -d "$(losetup -O NAME -n -j "$imgsrc" 2>/dev/null || true)" 2>/dev/null || true
losetup -d "$(losetup -O NAME -n -j "$targetimg" 2>/dev/null || true)" 2>/dev/null || true

# mount points
test -d /mnt || mkdir -p /mnt
test -d "$sourceboot" || mkdir -p "$sourceboot"
test -d "$sourceroot" || mkdir -p "$sourceroot"
test -d "$targetboot" || mkdir -p "$targetboot"
test -d "$targetroot" || mkdir -p "$targetroot"

# if target is image make it
if [ -n "$targetimg" ]; then
  echo "${cmdname}: Creating blank disk image."
  targetimgsize=$(du --block-size=M "$imgsrc" | cut -d "M" -f1)
  targetimgsize=$((targetimgsize + 200))
  truncate -s "${targetimgsize}M" "$targetimg"
  echo "${cmdname}: Attaching target disk image."
  targetdev=$(losetup --show -f -P "$targetimg")
fi

# mount source
echo "${cmdname}: Attaching source disk image."
sourcedev=$(losetup --show -f -P "$imgsrc")
echo "${cmdname}: Mounting source boot partition."
mount -o ro "${sourcedev}${target_p1}" "$sourceboot"
echo "${cmdname}: Mounting source root partition."
mount -o ro "${sourcedev}${target_p2}" "$sourceroot"

# wipe
echo "${cmdname}: Erasing current partition table on target."
wipefs -aq "$targetdev"

# create partitions using chosen fat size
echo "${cmdname}: Creating new partition table on target. FAT size ${FAT_MB}MiB"
parted -s "$targetdev" mklabel msdos \
  mkpart primary fat32 8192s "${FAT_MB}MiB" \
  mkpart primary ext2 "${FAT_MB}MiB" 100%

partprobe "$targetdev"
parted -s "$targetdev" print

bootuuid=$(blkid -o value -s PARTUUID "${targetdev}${target_p1}")
rootuuid=$(blkid -o value -s PARTUUID "${targetdev}${target_p2}")

# format boot
echo "${cmdname}: Formatting boot partition on target as FAT32."
mkfs.fat -n boot "${targetdev}${target_p1}"
echo "${cmdname}: Mounting target boot partition."
mount "${targetdev}${target_p1}" "$targetboot"
echo "${cmdname}: Getting file count on source."
numfiles=$(find "$sourceboot/" -type f -printf . | wc -c)
echo "${cmdname}: Copying $numfiles files from source image to target device."
rsync -axi "$sourceboot"/ "$targetboot"/ | pv -leps "$numfiles" >/dev/null

# update cmdline
echo "${cmdname}: Updating cmdline.txt options."
cp "$targetboot/cmdline.txt" "$targetboot/cmdline.old"
sed -i 's/rootfstype=[^ ]*/rootfstype=f2fs/g' "$targetboot/cmdline.txt"
sed -i 's/root=[^ ]*/root=PARTUUID='"$rootuuid"'/g' "$targetboot/cmdline.txt"
if [ -z "$targetimg" ]; then
  sed -i 's| init=/usr/lib/raspi-config/init_resize.sh||' "$targetboot/cmdline.txt"
  if ! grep -q splash "$targetboot/cmdline.txt"; then
    sed -i 's/ quiet//g' "$targetboot/cmdline.txt"
  fi
fi

echo "${cmdname}: Done processing the boot partition!"
sync

# format root as f2fs
echo "${cmdname}: Formatting root partition on target as F2FS."
mkfs.f2fs -o 20 -O extra_attr,inode_checksum,sb_checksum,compression -l root "${targetdev}${target_p2}"
echo "${cmdname}: Mounting target root partition."
mount "${targetdev}${target_p2}" "$targetroot"
echo "${cmdname}: Getting file count on source image."
numfiles=$(df -i "$sourceroot/" | perl -ane 'print $F[2] if $F[5] =~ m:^/:')
echo "${cmdname}: Copying $numfiles files from source image to target device."
rsync -axi "$sourceroot"/ "$targetroot"/ | pv -leps "$numfiles" >/dev/null

# fstab
echo "${cmdname}: Generating new fstab on target."
mv "$targetroot/etc/fstab" "$targetroot/etc/fstab.old"
cat > "$targetroot/etc/fstab" << EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$bootuuid  /boot   vfat    defaults                    0   2
PARTUUID=$rootuuid  /       f2fs    defaults,noatime,discard    0   1
EOF

# image-specific initramfs hooks
if [ -n "$targetimg" ]; then
  echo "${cmdname}: Setting up F2FS filesystem expansion."
  cat > "${targetroot}/etc/initramfs-tools/hooks/f2fsresize" << 'EOF'
#!/bin/sh
PREREQ=""
prereqs()
{
  echo "$PREREQ"
}
case "$1" in
prereqs) prereqs; exit 0;;
esac
. /usr/share/initramfs-tools/hook-functions
if [ ! -x "/sbin/resize.f2fs" ]; then exit 0; fi
copy_exec /sbin/resize.f2fs
exit 0
EOF
  chmod +x "${targetroot}/etc/initramfs-tools/hooks/f2fsresize"

  cat > "${targetroot}/etc/initramfs-tools/scripts/init-premount/f2fsresize" << EOF
#!/bin/sh
PREREQ=""
prereqs()
{
  echo "\$PREREQ"
}
case "\$1" in
prereqs) prereqs; exit 0;;
esac
. /scripts/functions
if [ ! -x "/sbin/resize.f2fs" ]; then
  panic "Resize.F2FS Executable Not Found"
fi
log_begin_msg "Expanding F2FS Filesystem"
/sbin/resize.f2fs "/dev/disk/by-partuuid/$rootuuid" || panic "F2FS Resize Failed"
log_end_msg
exit 0
EOF
  chmod +x "${targetroot}/etc/initramfs-tools/scripts/init-premount/f2fsresize"

  cat > "${targetroot}/etc/f2fsresize_cleanup" << 'EOF'
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

  kernelver=$(ls "${targetroot}/lib/modules/" | grep "v7+" | head -n 1 || true)
  test -r "$targetroot/usr/lib/raspi-config/init_resize.sh" && cp "$targetroot/usr/lib/raspi-config/init_resize.sh" "$targetroot/usr/lib/raspi-config/init_resize.old" || true
  if [ -n "$kernelver" ]; then
    linenum=$(grep -n "mount / -o remount,rw" "$targetroot/usr/lib/raspi-config/init_resize.sh" | head -n 1 | cut -d: -f1 || true)
    if [ -n "$linenum" ]; then
      linenum=$((linenum + 2))
      sed -i "${linenum}i echo \"initramfs initrd.img followkernel\" >> /boot/config.txt" "$targetroot/usr/lib/raspi-config/init_resize.sh"
      sed -i "${linenum}i sed -i \x27\x27\"$(grep -n "exit 0"  "/etc/rc.local" | tail -n 1 | cut -d: -f1)\"\\x27i /bin/bash /etc/f2fsresize_cleanup\x27 /etc/rc.local" "$targetroot/usr/lib/raspi-config/init_resize.sh" || true
    fi
  fi
fi

echo "${cmdname}: Syncing..."
sync

# chroot and install f2fs-tools
echo "${cmdname}: Building up chroot enviroment on target rootfs."
for i in dev proc sys dev/pts; do
  mount --bind "/$i" "$targetroot/$i"
done
mount --bind "$targetboot" "$targetroot/boot"

cat << EOF | chroot "$targetroot" env -i LANG=en_GB.utf8 LANGUAGE=en_GB.utf8 LC_ALL=en_GB.utf8 TERM=$TERM HOME=/root /bin/bash --login
echo "${cmdname}@${targetroot}: Stopping automatic ext4 filesystem expansion."
update-rc.d resize2fs_once remove || true
test -r /etc/init.d/resize2fs_once && rm /etc/init.d/resize2fs_once || true
echo "${cmdname}@${targetroot}: Installing f2fs-tools."
apt-get -qq update || true
apt-get -qq install -y f2fs-tools || true
apt-get -qq clean || true
test -z "$targetimg" || echo "${cmdname}@${targetroot}: Generating initramfs for F2FS filesystem expansion."
test -z "$targetimg" || mkinitramfs -o /boot/initrd.img $kernelver || true
exit 0
EOF

echo "${cmdname}: Tearing down chroot enviroment."
sync
sleep 1
for i in boot dev/pts sys proc dev; do
  umount "$targetroot/$i" || true
done

echo "${cmdname}: Done processing the root partition!"
echo "${cmdname}: Syncing..."
sync

echo "${cmdname}: Successfully completed Raspbian F2FS installation!"
echo "************************************************************"
df -hT --total "${targetdev}${target_p1}" "${targetdev}${target_p2}" || true
echo "************************************************************"

echo "${cmdname}: Unmounting everything."
umount "$sourceboot" 2>/dev/null || true
umount "$sourceroot" 2>/dev/null || true
umount "$targetboot" 2>/dev/null || true
umount "$targetroot" 2>/dev/null || true
umount "${sourcedev}"* 2>/dev/null || true
umount "${targetdev}"* 2>/dev/null || true
losetup -d "$sourcedev" 2>/dev/null || true
losetup -d "$targetdev" 2>/dev/null || true

echo "${cmdname}: Cleaning up."
test -r "$sourceboot" && rm -rf "$sourceboot"
test -r "$sourceroot" && rm -rf "$sourceroot"
test -r "$targetboot" && rm -rf "$targetboot"
test -r "$targetroot" && rm -rf "$targetroot"

echo "-------------------------------------------------------------------------------"
