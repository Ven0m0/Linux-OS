#!/usr/bin/env bash
#
# Title:         Raspberry Pi F2FS Image Flasher
# Description:   Converts a standard Raspberry Pi OS image to use an F2FS root
#                filesystem and flashes it to a target device or image file.
# Author:        Optimized based on user submission
# Version:       3.0.0
#
# Features:
# - Converts ext4 root partition to F2FS with optimized features.
# - Supports both block devices (e.g., /dev/sdX) and image files as targets.
# - Interactive source/target selection using fzf as a fallback.
# - Robust error handling and infallible cleanup via trap.
# - Pre-flight dependency checks.
# - Hardened user confirmation for destructive operations.
# - Optimized F2FS format options and mount options for SD cards.
# - Includes a mechanism for automatic root partition resize on first boot.
#
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C LANG=C SHELL="${BASH:-$(command -v bash)}" HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1

# --- Global Variables & Constants ---
# It's good practice to declare script-wide variables at the top.
# Using readonly makes them constants.
readonly C_RED='\033}")" && pwd -P)"

# Mount points and loop devices are managed globally for the cleanup trap
# Initialize to empty strings to avoid unbound variable errors with `set -u`
SOURCE_DEVICE=""
TARGET_DEVICE=""
SOURCE_IMG_SRC=""
TARGET_IMG_SRC=""
SOURCE_BOOT_MOUNT="/mnt/${SCRIPT_NAME}_source_boot"
SOURCE_ROOT_MOUNT="/mnt/${SCRIPT_NAME}_source_root"
TARGET_BOOT_MOUNT="/mnt/${SCRIPT_NAME}_target_boot"
TARGET_ROOT_MOUNT="/mnt/${SCRIPT_NAME}_target_root"

# --- Core Functions ---

#
# Prints script usage information.
#
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options][source.img|source.zip][ /dev/target | target.img ]

Flashes a Raspberry Pi Debian-based distribution image with an F2FS root
filesystem onto an SD card or into a new image file.

Options:
  -s SIZE_MB    Size of the FAT32 boot partition in MiB (minimum 1024). Default: 1024.
  -I            Interactively select the source image using fzf.
  -D            Interactively select the target device/image using fzf.
  -h            Display this help message and exit.

Examples:
  $SCRIPT_NAME -s 2048 raspberry-pi-os.img /dev/sdb
  $SCRIPT_NAME -I -D
  $SCRIPT_NAME raspberry-pi-os.zip new-f2fs-image.img
EOF
}

#
# Logs a message to stderr.
# Arguments:
#   $1: The message string.
#
log_error() {
  printf "${C_RED}${C_NC} %s\n" "$1" >&2
}

#
# Logs an informational message to stdout.
# Arguments:
#   $1: The message string.
#
log_info() {
  printf "${C_GREEN}[INFO]${C_NC} %s\n" "$1"
}

#
# Logs a warning message to stderr.
# Arguments:
#   $1: The message string.
#
log_warn() {
  printf "${C_YELLOW}${C_NC} %s\n" "$1" >&2
}

#
# Infallible cleanup function. This function is called on any script exit
# via the 'trap' command, ensuring all resources are released.
# It is designed to be idempotent (safe to run multiple times).
#
cleanup() {
  log_info "Initiating cleanup sequence..."
  # Use a subshell to suppress errors if umount/losetup fail (e.g., already unmounted)
  (
    set +e
    sync
    umount "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT"
    umount "${TARGET_ROOT_MOUNT}/boot" "${TARGET_ROOT_MOUNT}/dev/pts" "${TARGET_ROOT_MOUNT}/dev" "${TARGET_ROOT_MOUNT}/proc" "${TARGET_ROOT_MOUNT}/sys"
    if]; then umount "${SOURCE_DEVICE}"* &>/dev/null; fi
    if]; then umount "${TARGET_DEVICE}"* &>/dev/null; fi
    if]; then losetup -d "$SOURCE_DEVICE"; fi
    if]; then losetup -d "$TARGET_DEVICE"; fi

    # Clean up temporary mount point directories
    rmdir "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT" &>/dev/null |

| true
  )
  log_info "Cleanup complete."
}

#
# Checks for the existence of all required external commands.
# Exits with an error if any dependency is missing.
#
check_dependencies() {
  log_info "Verifying required tools are installed..."
  local missing_deps=()
  # POSIX-compliant check for command existence is `command -v`
  local deps=(
    awk basename blkid cat cd chmod chroot cp cut df dirname du
    find fzf grep head losetup lsblk mkdir mkfs.fat mkfs.f2fs mount
    mv parted partprobe perl pv read realpath rmdir rsync sed
    shopt sleep sort sudo sync tail touch truncate umount unzip
    wc wipefs whoami
  )

  for cmd in "${deps[@]}"; do
    if! command -v "$cmd" &>/dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ "${#missing_deps[@]}" -gt 0 ]]; then
    log_error "One or more required commands are not installed. Missing: ${missing_deps[*]}"
    exit 1
  fi
  log_info "All dependencies are satisfied."
}

# --- Interactive Selection Functions (fzf) ---

#
# Uses fzf to interactively select a source image file (.img or.zip).
#
pick_image() {
  # Use find with -print0 and a while loop for safe filename handling.
  local files=()
  while IFS= read -r -d $'\0' file; do
    files+=("$file")
  done < <(find. -maxdepth 3 -type f \( -iname '*.img' -o -iname '*.zip' \) -print0 2>/dev/null)

  if [[ "${#files[@]}" -eq 0 ]]; then
    log_error "No.img or.zip files found in the current directory or subdirectories (up to 3 levels deep)."
    return 1
  fi

  printf '%s\n' "${files[@]}" | fzf \
    --height 40% --border --tac \
    --prompt='Select source image > ' \
    --preview='ls -lh {}'
}

#
# Uses fzf to interactively select a target block device.
#
pick_device() {
  lsblk -dpno NAME,MODEL,SIZE,TYPE 2>/dev/null |
    grep -E '/dev/(sd|mmcblk).*\s+disk$' |
    fzf \
      --height 40% --border \
      --prompt='Select TARGET device (THIS WILL BE WIPED) > ' \
      --preview='lsblk -no NAME,MODEL,SIZE,RM,ROTA {}' |
    awk '{print $1}'
}

# --- Main Logic Functions ---

#
# Resolves the source image file path, either from arguments or interactively.
#
resolve_source_image() {
  local filename=""
  if]; then
    filename="$(pick_image)"
    if [[ -z "$filename" ]]; then
      log_error "No image selected. Aborting."
      exit 1
    fi
  elif [[ $# -ge 1 ]]; then
    filename="$1"
  else
    log_error "No source image provided."
    log_error "Use -I to select interactively, or provide a path as the first argument."
    usage
    exit 1
  fi

  if [[! -f "$filename" ]]; then
    log_error "Source file not found: $filename"
    exit 1
  fi

  # Return the absolute path for consistency
  realpath "$filename"
}

#
# Resolves the target path, either from arguments or interactively.
#
resolve_target_device() {
  local target_path=""
  if]; then
    target_path="$(pick_device)"
    if [[ -z "$target_path" ]]; then
      log_error "No target device selected. Aborting."
      exit 1
    fi
  elif [[ $# -ge 1 ]]; then
    target_path="$1"
  else
    log_error "No target device/image provided."
    log_error "Use -D to select interactively, or provide a path as the second argument."
    usage
    exit 1
  fi

  # Return the path
  echo "$target_path"
}

#
# Prepares the target device: confirms overwrite, wipes, and partitions.
# Arguments:
#   $1: Target device path (e.g., /dev/sdb)
#   $2: FAT32 partition size in MiB
#
prepare_target() {
  local target_dev="$1"
  local fat_mb="$2"

  log_warn "The device '$target_dev' is about to be completely erased."
  printf "\n"
  sudo parted -s "$target_dev" print |

| true
  printf "\n"
  log_warn "This operation is DESTRUCTIVE and IRREVERSIBLE."
  printf "To proceed, you must type the full device path ('%s') and press Enter: " "$target_dev"
  
  local confirmation=""
  read -r confirmation
  if [[ "$confirmation"!= "$target_dev" ]]; then
    log_error "Confirmation failed. Aborting."
    exit 1
  fi

  log_info "Proceeding with erasure of $target_dev."

  log_info "Unmounting any existing partitions on $target_dev..."
  # Use a subshell to ignore errors if nothing is mounted
  ( set +e; sudo umount "${target_dev}"* &>/dev/null )

  log_info "Erasing existing partition table and filesystem signatures on $target_dev..."
  sudo wipefs -aq "$target_dev"
  sudo sgdisk --zap-all "$target_dev" # More thorough than wipefs for GPT/MBR structures

  log_info "Creating new MBR partition table on target. FAT size: ${fat_mb}MiB"
  # Use sgdisk for more reliable partitioning and alignment.
  # 8192s offset = 4MiB, which is a common and safe alignment.
  sudo sgdisk \
    -n "1:8192s:+${fat_mb}M" -t 1:0c00 \
    -n "2:0:-0"             -t 2:8300 \
    "$target_dev"

  # partprobe is essential to ask the kernel to re-read the partition table
  sudo partprobe "$target_dev"
  sleep 2 # Give the kernel a moment to create the device nodes
  sudo parted -s "$target_dev" print
}

#
# Main function to orchestrate the script's execution.
#
main() {
  # Set the trap at the very beginning to catch all exits.
  trap cleanup EXIT

  # --- Argument Parsing ---
  local FAT_MB=1024
  local SELECT_IMAGE=0
  local SELECT_DEVICE=0

  while getopts "s:IDh" opt; do
    case "$opt" in
      s) FAT_MB=$OPTARG ;;
      I) SELECT_IMAGE=1 ;;
      D) SELECT_DEVICE=1 ;;
      h) usage; exit 0 ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))

  # --- Sanity Checks ---
  if [[ "$(whoami)" == "root" ]]; then
    log_error "This script should not be run directly as root. Use sudo."
    exit 1
  fi
  sudo -v # Refresh sudo timestamp

  if!+$ ]] ||]; then
    log_warn "Invalid FAT partition size. Must be an integer >= 1024. Using 1024 MiB."
    FAT_MB=1024
  fi

  check_dependencies

  # --- Resolve Source and Target ---
  local source_path
  source_path="$(resolve_source_image "$@")"
  # Shift away the source argument if it was positional
  if]; then shift 1; fi

  local target_path
  target_path="$(resolve_target_device "$@")"
  # Shift away the target argument if it was positional
  if]; then shift 1; fi

  # --- Determine Target Type (Device vs. Image File) ---
  local target_is_device=0
  local target_is_image=0
  local p1_suffix=""
  local p2_suffix=""

  if [[ -b "$target_path" ]]; then
    target_is_device=1
    TARGET_DEVICE="$target_path"
    case "$TARGET_DEVICE" in
      /dev/mmcblk*) p1_suffix="p1"; p2_suffix="p2" ;;
      *)            p1_suffix="1";  p2_suffix="2"  ;;
    esac
  elif! [[ -e "$target_path" ]]; then
    target_is_image=1
    TARGET_IMG_SRC="$target_path"
    p1_suffix="p1"
    p2_suffix="p2"
  else
    log_error "Target '$target_path' is an existing file but not a block device. Aborting."
    exit 1
  fi

  # --- Unzip Source if Necessary ---
  if [[ "${source_path##*.}" == "zip" ]]; then
    log_info "Source is a ZIP archive. Extracting..."
    SOURCE_IMG_SRC="${source_path%.*}.img"
    if]; then
      unzip -p "$source_path" > "$SOURCE_IMG_SRC"
    else
      log_info "Found existing.img file, using it: $SOURCE_IMG_SRC"
    fi
  elif [[ "${source_path##*.}" == "img" ]]; then
    SOURCE_IMG_SRC="$source_path"
  else
    log_error "Source must be a.img or.zip file."
    exit 1
  fi

  # --- Prepare Mount Points ---
  log_info "Creating temporary mount points..."
  mkdir -p "$SOURCE_BOOT_MOUNT" "$SOURCE_ROOT_MOUNT" "$TARGET_BOOT_MOUNT" "$TARGET_ROOT_MOUNT"

  # --- Prepare Target ---
  if [[ "$target_is_device" -eq 1 ]]; then
    prepare_target "$TARGET_DEVICE" "$FAT_MB"
  elif [[ "$target_is_image" -eq 1 ]]; then
    log_info "Target is an image file. Creating blank disk image..."
    # Calculate size: source image size + 200MiB buffer
    local source_size_mb
    source_size_mb=$(du --block-size=M "$SOURCE_IMG_SRC" | cut -d'M' -f1)
    local target_size_mb=$((source_size_mb + 200))
    truncate -s "${target_size_mb}M" "$TARGET_IMG_SRC"

    log_info "Attaching target disk image as a loop device..."
    TARGET_DEVICE=$(sudo losetup --show -f -P "$TARGET_IMG_SRC")
    prepare_target "$TARGET_DEVICE" "$FAT_MB"
  fi

  # --- Attach Source Image ---
  log_info "Attaching source disk image as a loop device..."
  SOURCE_DEVICE=$(sudo losetup --show -f -P "$SOURCE_IMG_SRC")

  # --- Mount Partitions ---
  log_info "Mounting source partitions (read-only)..."
  sudo mount -o ro "${SOURCE_DEVICE}${p1_suffix}" "$SOURCE_BOOT_MOUNT"
  sudo mount -o ro "${SOURCE_DEVICE}${p2_suffix}" "$SOURCE_ROOT_MOUNT"

  # --- Format and Copy Boot Partition ---
  log_info "Formatting target boot partition as FAT32..."
  sudo mkfs.fat -F 32 -n boot "${TARGET_DEVICE}${p1_suffix}"
  log_info "Mounting target boot partition..."
  sudo mount "${TARGET_DEVICE}${p1_suffix}" "$TARGET_BOOT_MOUNT"

  log_info "Copying boot files from source to target..."
  local numfiles
  numfiles=$(find "$SOURCE_BOOT_MOUNT/" -type f | wc -l)
  sudo rsync -aHAX --info=progress2 "$SOURCE_BOOT_MOUNT"/ "$TARGET_BOOT_MOUNT"/

  # --- Configure Boot Partition (cmdline.txt) ---
  log_info "Updating cmdline.txt on target..."
  local boot_partuuid
  local root_partuuid
  boot_partuuid=$(sudo blkid -o value -s PARTUUID "${TARGET_DEVICE}${p1_suffix}")
  root_partuuid=$(sudo blkid -o value -s PARTUUID "${TARGET_DEVICE}${p2_suffix}")

  sudo cp "$TARGET_BOOT_MOUNT/cmdline.txt" "$TARGET_BOOT_MOUNT/cmdline.txt.orig"
  sudo sed -i 's/rootfstype=[^ ]*/rootfstype=f2fs/' "$TARGET_BOOT_MOUNT/cmdline.txt"
  sudo sed -i 's/root=[^ ]*/root=PARTUUID='"$root_partuuid"'/' "$TARGET_BOOT_MOUNT/cmdline.txt"

  if [[ "$target_is_device" -eq 1 ]]; then
    log_info "Target is a physical device, removing init_resize.sh hook..."
    sudo sed -i 's| init=/usr/lib/raspi-config/init_resize.sh||' "$TARGET_BOOT_MOUNT/cmdline.txt"
  fi

  # --- Format and Copy Root Partition ---
  log_info "Formatting target root partition as F2FS..."
  # Optimized F2FS options for reliability and performance on SD cards
  sudo mkfs.f2fs \
    -O extra_attr,inode_checksum,sb_checksum,compression,lost_found \
    -l root \
    "${TARGET_DEVICE}${p2_suffix}"

  log_info "Mounting target root partition..."
  sudo mount "${TARGET_DEVICE}${p2_suffix}" "$TARGET_ROOT_MOUNT"

  log_info "Copying root filesystem files from source to target..."
  sudo rsync -aHAX --info=progress2 "$SOURCE_ROOT_MOUNT"/ "$TARGET_ROOT_MOUNT"/

  # --- Configure Root Partition (fstab) ---
  log_info "Generating new fstab on target..."
  sudo mv "$TARGET_ROOT_MOUNT/etc/fstab" "$TARGET_ROOT_MOUNT/etc/fstab.orig"
  # Optimized fstab with modern options for performance and flash longevity
  sudo bash -c "cat > \"$TARGET_ROOT_MOUNT/etc/fstab\"" << EOF
proc                  /proc   proc    defaults                  0 0
PARTUUID=$boot_partuuid  /boot   vfat    defaults                  0 2
PARTUUID=$root_partuuid  /       f2fs    defaults,lazytime,discard,compress_algorithm=zstd:3,atgc,gc_merge 0 1
EOF

  # --- Configure F2FS Resize on First Boot (for image targets only) ---
  if [[ "$target_is_image" -eq 1 ]]; then
    log_info "Setting up F2FS filesystem expansion for first boot..."
    # This is a complex and brittle process that patches the OS's own scripts.
    # It may break with future Raspberry Pi OS updates.

    # 1. Add resize.f2fs to initramfs
    sudo bash -c "cat > '${TARGET_ROOT_MOUNT}/etc/initramfs-tools/hooks/f2fsresize'" << 'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "\$PREREQ"; }
case "\$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
if [! -x "/sbin/resize.f2fs" ]; then exit 0; fi
copy_exec /sbin/resize.f2fs
EOF
    sudo chmod +x "${TARGET_ROOT_MOUNT}/etc/initramfs-tools/hooks/f2fsresize"

    # 2. Create the initramfs script to run the resize
    sudo bash -c "cat > '${TARGET_ROOT_MOUNT}/etc/initramfs-tools/scripts/init-premount/f2fsresize'" << EOF
#!/bin/sh
PREREQ=""
prereqs() { echo "\$PREREQ"; }
case "\$1" in prereqs) prereqs; exit 0;; esac
. /scripts/functions
if [! -x "/sbin/resize.f2fs" ]; then
  panic "resize.f2fs executable not found in initramfs"
fi
log_begin_msg "Expanding F2FS filesystem"
# The PARTUUID is hardcoded here from the parent script's environment
/sbin/resize.f2fs "/dev/disk/by-partuuid/$root_partuuid" |

| panic "F2FS resize failed"
log_end_msg
exit 0
EOF
    sudo chmod +x "${TARGET_ROOT_MOUNT}/etc/initramfs-tools/scripts/init-premount/f2fsresize"

    # 3. Create a cleanup script to remove the resize hooks after first boot
    sudo bash -c "cat > '${TARGET_ROOT_MOUNT}/etc/f2fsresize_cleanup.sh'" << 'EOF'
#!/bin/bash
# This script runs once on the first boot after resize to clean up.
set -e
# Remove the rc.local entry that runs this script
sed -i '/\/bin\/bash \/etc\/f2fsresize_cleanup.sh/d' /etc/rc.local
# Remove the initramfs from boot config
sed -i '/^initramfs initrd.img followkernel/d' /boot/config.txt
# Remove the generated initramfs and its hooks
rm -f /boot/initrd.img*
rm -f /etc/initramfs-tools/scripts/init-premount/f2fsresize
rm -f /etc/initramfs-tools/hooks/f2fsresize
# Remove this cleanup script itself
rm -f /etc/f2fsresize_cleanup.sh
# Re-enable original resize service in case it's needed for other things
systemctl enable resize2fs_once
EOF
    sudo chmod +x "${TARGET_ROOT_MOUNT}/etc/f2fsresize_cleanup.sh"
  fi

  # --- Chroot and Finalize ---
  log_info "Setting up chroot environment on target rootfs..."
  sudo mount --bind /dev "${TARGET_ROOT_MOUNT}/dev"
  sudo mount --bind /dev/pts "${TARGET_ROOT_MOUNT}/dev/pts"
  sudo mount --bind /proc "${TARGET_ROOT_MOUNT}/proc"
  sudo mount --bind /sys "${TARGET_ROOT_MOUNT}/sys"
  sudo mount --bind "$TARGET_BOOT_MOUNT" "${TARGET_ROOT_MOUNT}/boot"

  # Determine the latest kernel version robustly
  local kernel_ver
  kernel_ver=$(ls "${TARGET_ROOT_MOUNT}/lib/modules/" | sort -V | tail -n 1)
  if [[ -z "$kernel_ver" ]]; then
    log_error "Could not determine kernel version from target image. Cannot proceed with chroot."
    exit 1
  fi
  log_info "Identified target kernel version: $kernel_ver"

  log_info "Entering chroot to install f2fs-tools and generate initramfs..."
  sudo chroot "$TARGET_ROOT_MOUNT" /bin/bash <<CHROOT_EOF
set -e
export DEBIAN_FRONTEND=noninteractive

log_info_chroot() { printf "${C_GREEN}${C_NC} %s\n" "\$1"; }

log_info_chroot "Disabling original ext4 resize service..."
systemctl disable resize2fs_once

log_info_chroot "Updating package lists..."
apt-get update -y

log_info_chroot "Installing f2fs-tools..."
apt-get install -y f2fs-tools

log_info_chroot "Cleaning apt cache..."
apt-get clean

if [[ "$target_is_image" -eq 1 ]]; then
  log_info_chroot "Adding cleanup script to rc.local..."
  # Insert the call to the cleanup script before the final 'exit 0'
  if grep -q "exit 0" /etc/rc.local; then
    sed -i '/^exit 0/i /bin/bash /etc/f2fsresize_cleanup.sh |

| true' /etc/rc.local
  else
    echo "/bin/bash /etc/f2fsresize_cleanup.sh |

| true" >> /etc/rc.local
  fi

  log_info_chroot "Adding initramfs to /boot/config.txt..."
  echo "initramfs initrd.img followkernel" >> /boot/config.txt

  log_info_chroot "Generating initramfs for F2FS filesystem expansion..."
  mkinitramfs -o "/boot/initrd.img-${kernel_ver}" "$kernel_ver"
  # Create a generic symlink that config.txt can use
  ln -sf "initrd.img-${kernel_ver}" /boot/initrd.img
fi

exit 0
CHROOT_EOF

  log_info "Chroot operations complete. Tearing down chroot environment."
  # The cleanup trap will handle the unmounting.

  # --- Final Report ---
  log_info "Syncing filesystems..."
  sudo sync
  sleep 2

  printf "\n"
  log_info "************************************************************"
  log_info "Successfully completed Raspberry Pi F2FS installation!"
  log_info "Target device summary:"
  sudo df -hT --total "${TARGET_DEVICE}${p1_suffix}" "${TARGET_DEVICE}${p2_suffix}" |

| true
  log_info "************************************************************"
  printf "\n"

  if [[ "$target_is_image" -eq 1 ]]; then
    log_info "The image file '$TARGET_IMG_SRC' is ready to be written to an SD card."
  else
    log_info "The SD card '$TARGET_DEVICE' is ready to be used in a Raspberry Pi."
  fi
}

# --- Script Entry Point ---
# The script execution starts here by calling the main function.
# All arguments passed to the script are forwarded to main.
main "$@"
