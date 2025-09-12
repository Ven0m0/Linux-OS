#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar; export LC_ALL=C LANG=C
readonly SCRIPT_NAME="${0##*/}"
readonly C_RED='\033[0;31m' C_GREEN='\033[0;32m' C_YELLOW='\033[1;33m' C_NC='\033[0m'
TARGET_DEVICE="" TARGET_IMG_SRC=""
SOURCE_BOOT_MOUNT="/mnt/${SCRIPT_NAME}_source_boot" SOURCE_ROOT_MOUNT="/mnt/${SCRIPT_NAME}_source_root"
TARGET_BOOT_MOUNT="/mnt/${SCRIPT_NAME}_target_boot" TARGET_ROOT_MOUNT="/mnt/${SCRIPT_NAME}_target_root"

log_msg() { case "$1" in
  err) printf "${C_RED}[ERROR]${C_NC} %s\n" "$2" >&2 ;;
  info) printf "${C_GREEN}[INFO]${C_NC} %s\n" "$2" ;;
  warn) printf "${C_YELLOW}[WARN]${C_NC} %s\n" "$2" >&2 ;;
esac; }

cleanup() { log_msg info "Cleaning up..."; ( set +e
  sync
  umount -f "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT" &>/dev/null
  umount -f "${TARGET_ROOT_MOUNT}"/{boot,dev/pts,dev,proc,sys} &>/dev/null
  [[ -n "$SOURCE_DEVICE" ]] && losetup -d "$SOURCE_DEVICE"
  [[ -n "$TARGET_DEVICE" ]] && losetup -d "$TARGET_DEVICE"
  rmdir "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT" &>/dev/null
); log_msg info "Cleanup complete."; }

check_deps() {
  local missing=()
  for cmd in awk basename blkid cat cd chmod chroot cp cut df dirname du find fzf grep head losetup lsblk mkdir mkfs.fat mkfs.f2fs mount mv parted partprobe pv read realpath rmdir rsync sed sleep sort sudo sync tail truncate umount unzip wipefs; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  (( ${#missing[@]} > 0 )) && { log_msg err "Missing commands: ${missing[*]}"; exit 1; }
}

pick_image() { find . -maxdepth 3 -type f \( -iname '*.img' -o -iname '*.zip' \) -print0 2>/dev/null |
  xargs -0 fzf --height 40% --border --tac --prompt='Select source image > ' --preview='ls -lh {}'; }

pick_device() { lsblk -dpno NAME,MODEL,SIZE,TYPE 2>/dev/null | grep -E '/dev/(sd|mmcblk).*\s+disk$' |
  fzf --height 40% --border --prompt='Select TARGET (WILL BE WIPED) > ' --preview='lsblk {}' | awk '{print $1}'; }

main() {
  trap cleanup EXIT
  local FAT_MB=1024 SELECT_IMAGE=0 SELECT_DEVICE=0
  while getopts "s:IDh" opt; do case "$opt" in
    s) FAT_MB=$OPTARG ;; I) SELECT_IMAGE=1 ;; D) SELECT_DEVICE=1 ;;
    h) echo "Usage: $SCRIPT_NAME [-s SIZE_MB] [-I] [-D] [source] [target]"; exit 0 ;;
    *) exit 1 ;;
  esac; done; shift $((OPTIND - 1))

  [[ "$(id -u)" -eq 0 ]] && { log_msg err "Do not run as root. Use sudo."; exit 1; }
  sudo -v
  check_deps

  local source_path=""
  if (( SELECT_IMAGE )); then source_path="$(pick_image)"; else source_path="${1:-}"; fi
  [[ -z "$source_path" ]] && { log_msg err "No source image provided. Use -I or specify a path."; exit 1; }
  [[ ! -f "$source_path" ]] && { log_msg err "Source file not found: $source_path"; exit 1; }
  source_path="$(realpath "$source_path")"; shift

  local target_path=""
  if (( SELECT_DEVICE )); then target_path="$(pick_device)"; else target_path="${1:-}"; fi
  [[ -z "$target_path" ]] && { log_msg err "No target device provided. Use -D or specify a path."; exit 1; }

  local target_is_device=0 target_is_image=0 p1_suffix="" p2_suffix=""
  if [[ -b "$target_path" ]]; then
    target_is_device=1; TARGET_DEVICE="$target_path"
    [[ "$TARGET_DEVICE" == /dev/mmcblk* ]] && { p1_suffix="p1"; p2_suffix="p2"; } || { p1_suffix="1"; p2_suffix="2"; }
  elif [[ ! -e "$target_path" ]]; then
    target_is_image=1; TARGET_IMG_SRC="$target_path"
    p1_suffix="p1"; p2_suffix="p2"
  else log_msg err "Target '$target_path' exists and is not a block device."; exit 1; fi

  log_msg info "Preparing source..."
  local SOURCE_IMG_SRC=""
  case "${source_path##*.}" in
    zip) SOURCE_IMG_SRC="${source_path%.*}.img"; unzip -p "$source_path" > "$SOURCE_IMG_SRC" ;;
    img) SOURCE_IMG_SRC="$source_path" ;;
    *) log_msg err "Source must be .img or .zip"; exit 1 ;;
  esac

  mkdir -p "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT"

  if (( target_is_device )); then
    log_msg warn "Device '$TARGET_DEVICE' will be completely erased."
    sudo parted -s "$TARGET_DEVICE" print
    printf "Type '%s' to confirm: " "$TARGET_DEVICE"; read -r confirmation
    [[ "$confirmation" != "$TARGET_DEVICE" ]] && { log_msg err "Confirmation failed."; exit 1; }
    sudo umount "${TARGET_DEVICE}"* &>/dev/null || true
    sudo wipefs -aq "$TARGET_DEVICE"; sudo sgdisk --zap-all "$TARGET_DEVICE"
    sudo sgdisk -n "1:8192s:+${FAT_MB}M" -t 1:0c00 -n "2:0:-0" -t 2:8300 "$TARGET_DEVICE"
  elif (( target_is_image )); then
    log_msg info "Creating blank image file..."
    local source_size_mb=$(du -m "$SOURCE_IMG_SRC" | cut -f1)
    truncate -s "$((source_size_mb + 200))M" "$TARGET_IMG_SRC"
    TARGET_DEVICE=$(sudo losetup --show -f -P "$TARGET_IMG_SRC")
    sudo sgdisk -n "1:8192s:+${FAT_MB}M" -t 1:0c00 -n "2:0:-0" -t 2:8300 "$TARGET_DEVICE"
  fi
  sudo partprobe "$TARGET_DEVICE"; sleep 2

  SOURCE_DEVICE=$(sudo losetup --show -f -P "$SOURCE_IMG_SRC")
  sudo mount -o ro "${SOURCE_DEVICE}${p1_suffix}" "$SOURCE_BOOT_MOUNT"
  sudo mount -o ro "${SOURCE_DEVICE}${p2_suffix}" "$SOURCE_ROOT_MOUNT"

  log_msg info "Formatting and copying boot partition..."
  sudo mkfs.fat -F 32 -n boot "${TARGET_DEVICE}${p1_suffix}"
  sudo mount "${TARGET_DEVICE}${p1_suffix}" "$TARGET_BOOT_MOUNT"
  sudo rsync -aHAX --info=progress2 "$SOURCE_BOOT_MOUNT/" "$TARGET_BOOT_MOUNT/"

  log_msg info "Configuring boot options..."
  local boot_partuuid; boot_partuuid=$(sudo blkid -o value -s PARTUUID "${TARGET_DEVICE}${p1_suffix}")
  local root_partuuid; root_partuuid=$(sudo blkid -o value -s PARTUUID "${TARGET_DEVICE}${p2_suffix}")
  sudo sed -i -e "s/rootfstype=[^ ]*/rootfstype=f2fs/" \
    -e "s/root=[^ ]*/root=PARTUUID=$root_partuuid/" \
    -e 's| init=/usr/lib/raspi-config/init_resize.sh||' "$TARGET_BOOT_MOUNT/cmdline.txt"

  log_msg info "Formatting and copying root partition..."
  sudo mkfs.f2fs -O extra_attr,inode_checksum,sb_checksum,compression,lost_found -l root "${TARGET_DEVICE}${p2_suffix}"
  sudo mount "${TARGET_DEVICE}${p2_suffix}" "$TARGET_ROOT_MOUNT"
  sudo rsync -aHAX --info=progress2 "$SOURCE_ROOT_MOUNT/" "$TARGET_ROOT_MOUNT/"

  log_msg info "Generating new fstab..."
  echo -e "proc /proc proc defaults 0 0\nPARTUUID=$boot_partuuid /boot vfat defaults 0 2\nPARTUUID=$root_partuuid / f2fs defaults,lazytime,discard,compress_algorithm=zstd:3 0 1" | sudo tee "$TARGET_ROOT_MOUNT/etc/fstab" > /dev/null

  if (( target_is_image )); then
    log_msg info "Setting up first-boot F2FS resize..."
    echo '#!/bin/sh
. /usr/share/initramfs-tools/hook-functions
[ -x "/sbin/resize.f2fs" ] && copy_exec /sbin/resize.f2fs' | sudo tee "$TARGET_ROOT_MOUNT/etc/initramfs-tools/hooks/f2fsresize" >/dev/null
    echo "#!/bin/sh
. /scripts/functions
/sbin/resize.f2fs /dev/disk/by-partuuid/$root_partuuid || panic 'F2FS resize failed'" | sudo tee "$TARGET_ROOT_MOUNT/etc/initramfs-tools/scripts/init-premount/f2fsresize" >/dev/null
    echo '#!/bin/bash
set -e
sed -i "/\/bin\/bash \/etc\/f2fsresize_cleanup.sh/d" /etc/rc.local
sed -i "/^initramfs initrd.img followkernel/d" /boot/config.txt
rm -f /boot/initrd.img* /etc/initramfs-tools/scripts/init-premount/f2fsresize /etc/initramfs-tools/hooks/f2fsresize "$0"' | sudo tee "$TARGET_ROOT_MOUNT/etc/f2fsresize_cleanup.sh" >/dev/null
    sudo chmod +x "${TARGET_ROOT_MOUNT}/etc/initramfs-tools/hooks/f2fsresize" \
      "${TARGET_ROOT_MOUNT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" \
      "${TARGET_ROOT_MOUNT}/etc/f2fsresize_cleanup.sh"
  fi

  log_msg info "Finalizing setup in chroot..."
  sudo mount --bind /dev "${TARGET_ROOT_MOUNT}/dev"; sudo mount --bind /dev/pts "${TARGET_ROOT_MOUNT}/dev/pts"
  sudo mount -t proc proc "${TARGET_ROOT_MOUNT}/proc"; sudo mount -t sysfs sys "${TARGET_ROOT_MOUNT}/sys"
  sudo mount --bind "$TARGET_BOOT_MOUNT" "${TARGET_ROOT_MOUNT}/boot"

  local kernel_ver; kernel_ver=$(ls "${TARGET_ROOT_MOUNT}/lib/modules/" | sort -V | tail -n 1)
  [[ -z "$kernel_ver" ]] && { log_msg err "Could not determine kernel version."; exit 1; }

  sudo chroot "$TARGET_ROOT_MOUNT" /bin/bash -s "$target_is_image" "$kernel_ver" <<'CHROOT_EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
target_is_image=$1; kernel_ver=$2
systemctl disable resize2fs_once
apt-get update -y && apt-get install -y f2fs-tools && apt-get clean
if (( target_is_image )); then
  sed -i '/^exit 0/i /bin/bash /etc/f2fsresize_cleanup.sh' /etc/rc.local
  echo "initramfs initrd.img followkernel" >> /boot/config.txt
  mkinitramfs -o "/boot/initrd.img-${kernel_ver}" "$kernel_ver"
  ln -sf "initrd.img-${kernel_ver}" /boot/initrd.img
fi
CHROOT_EOF

  log_msg info "Syncing filesystems..."
  sudo sync
  log_msg info "Process complete."
  if (( target_is_image )); then
    log_msg info "Image file '$TARGET_IMG_SRC' is ready."
  else
    log_msg info "SD card '$TARGET_DEVICE' is ready."
  fi
}

main "$@"
