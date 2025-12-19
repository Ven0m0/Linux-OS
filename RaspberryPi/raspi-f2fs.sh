#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
#──────────────────────────────────────────────────────────────────────────────
# raspi-f2fs.sh - Raspberry Pi SD Card Flasher with F2FS Root Filesystem
#──────────────────────────────────────────────────────────────────────────────
# Description:
#   Automates the process of flashing a Raspberry Pi image to an SD card or USB
#   device, converting the root filesystem from ext4 to F2FS for improved
#   performance and longevity on flash media.  Supports local images, URLs, and
#   automatic DietPi downloads.  Includes optional PiShrink-like functionality
#   to reduce image size before flashing.
#
# Features:
#   - Automatic F2FS conversion for root partition
#   - FAT32 boot partition with proper PARTUUID configuration
#   - Interactive device selection using fzf
#   - URL download support (plain/xz-compressed)
#   - Optional image shrinking before flash (saves time)
#   - Safety checks:  USB/MMC detection, size validation, device locking
#   - Comprehensive error handling and cleanup
#
# Requirements:
#   - Root privileges (sudo)
#   - Kernel with F2FS support
#   - f2fs-tools, rsync, parted, xz-utils
#   - Optional: fzf (for interactive selection)
#
# Usage Examples:
#   # Interactive mode (prompts for source and target)
#   sudo ./raspi-f2fs.sh
#
#   # Flash DietPi to /dev/sdb with SSH enabled
#   sudo ./raspi-f2fs.sh -i dietpi -d /dev/sdb -s
#
#   # Flash from URL with shrinking
#   sudo ./raspi-f2fs.sh -i https://example.com/image.img. xz -d /dev/sdc -z
#
#   # Flash local image with custom boot size
#   sudo ./raspi-f2fs.sh -i raspios. img -d /dev/sdd -b 1024M
#
# Safety Notes:
#   - DESTRUCTIVE: All data on target device will be erased
#   - Use -U flag carefully (bypasses USB/MMC check)
#   - Device locking prevents concurrent operations
#   - Always verify target device before running
#──────────────────────────────────────────────────────────────────────────────

set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C
IFS=$'\n\t'

# Script directory resolution (portable)
s=${BASH_SOURCE[0]}
[[ $s != /* ]] && s=$PWD/$s
cd -P -- "${s%/*}"

#──────────────────────────────────────────────────────────────────────────────
# CORE UTILITIES
#──────────────────────────────────────────────────────────────────────────────

# Optimized date formatting (uses printf builtin)
fdate() { printf '%(%T)T' '-1'; }

# Fast file reader (avoids cat fork)
fcat() { printf '%s\n' "$(<"${1}")"; }

# Check if command exists (no-fork version)
has() { command -v -- "$1" &>/dev/null; }

#──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION & CONSTANTS
#──────────────────────────────────────────────────────────────────────────────

# Configuration associative array (default values)
declare -A cfg=(
  [boot_size]="512M" # Boot partition size
  [ssh]=0            # Enable SSH on first boot
  [dry_run]=0        # Dry-run mode (no actual writes)
  [keep_source]=0    # Keep extracted source files
  [no_usb_check]=0   # Bypass USB/MMC safety check
  [no_size_check]=0  # Bypass size validation
  [shrink]=0         # Enable PiShrink-like optimization
)

# DietPi default URL (Raspberry Pi 2/3/4/5 ARMv8 Trixie)
declare -r DIETPI_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"

# ANSI color codes (optimized:  computed once)
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m'
CYN=$'\e[36m' WHT=$'\e[37m' LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
declare -r RED GRN YLW BLU MGN DEF BLD

# Global state variables (cleanup tracking)
declare -g SRC_PATH="" TGT_PATH="" SRC_IMG="" WORKDIR=""
declare -g LOOP_DEV="" TGT_DEV="" BOOT_PART="" ROOT_PART=""
declare -g LOCK_FD=-1 LOCK_FILE=""
declare -ga MOUNTED_DIRS=() # Stack of mounted directories

#──────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
#──────────────────────────────────────────────────────────────────────────────

# Enhanced echo (interprets color codes)
xecho() { printf '%b\n' "$*"; }

# Logging levels with timestamps and color coding
log() { xecho "[$(fdate)] ${BLU}${BLD}[*]${DEF} $*"; }
msg() { xecho "[$(fdate)] ${GRN}${BLD}[+]${DEF} $*"; }
warn() { xecho "[$(fdate)] ${YLW}${BLD}[!]${DEF} $*" >&2; }
err() { xecho "[$(fdate)] ${RED}${BLD}[-]${DEF} $*" >&2; }
dbg() {
  if [[ ${DEBUG:-0} -eq 1 ]]; then
    xecho "[$(fdate)] ${MGN}[DBG]${DEF} $*"
  fi
}

#──────────────────────────────────────────────────────────────────────────────
# DEVICE VALIDATION & SAFETY CHECKS
#──────────────────────────────────────────────────────────────────────────────

# Get device transport type (usb, mmc, sata, nvme, etc.)
# Returns:  Transport type string or "unknown"
get_drive_trans() {
  local dev="${1:?missing device}"
  lsblk -dno TRAN "$dev" 2>&1 || echo "unknown"
}

# Assert device is USB or MMC (safety check)
# Prevents accidental writes to internal drives
# Bypassed with -U flag or for loop devices
assert_usb_dev() {
  local dev="${1:?missing device}"
  ((cfg[no_usb_check])) && return 0
  [[ $dev == /dev/loop* ]] && return 0

  local trans
  trans=$(get_drive_trans "$dev")

  if [[ $trans != usb && $trans != mmc ]]; then
    err "Device $dev is not USB/MMC (detected:  $trans)"
    err "Use -U to bypass this check (DANGEROUS)"
    cleanup
    exit 1
  fi
}

# Verify image fits on target device
# Compares byte sizes to prevent truncation
assert_size() {
  local img="${1:?missing image}" dev="${2:?missing device}"
  ((cfg[no_size_check])) && return 0
  [[ ! -b $dev ]] && return 0

  local img_bytes dev_bytes
  img_bytes=$(stat -c%s "$img")
  dev_bytes=$(blockdev --getsize64 "$dev")

  if ((img_bytes > dev_bytes)); then
    err "Image size ($((img_bytes / 1024 / 1024))MB) exceeds target ($((dev_bytes / 1024 / 1024))MB)"
    cleanup
    exit 1
  fi
}

#──────────────────────────────────────────────────────────────────────────────
# INTERACTIVE DEVICE SELECTION
#──────────────────────────────────────────────────────────────────────────────

# Interactive target device selection using fzf
# Filters for USB/MMC disk devices (unless -U flag set)
# Returns:  Device path (e.g., /dev/sdb)
select_target_interactive() {
  if ! has fzf; then
    err "fzf required for interactive selection"
    err "Install:  apt install fzf"
    cleanup
    exit 1
  fi

  log "Scanning for removable drives..."
  local selection
  selection=$(
    lsblk -p -d -n -o NAME,MODEL,VENDOR,SIZE,TRAN,TYPE,HOTPLUG \
      | awk -v skip="${cfg[no_usb_check]}" '
      tolower($0) ~ /disk/ && (skip=="1" || tolower($0) ~ /usb|mmc/)
    ' \
      | fzf --header="SELECT TARGET DEVICE (WARNING: ALL DATA WILL BE ERASED)" \
        --header-lines=0 \
        --prompt="Device> " \
        --preview='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT {1}' \
        --preview-window=right:50%
  )

  if [[ -z $selection ]]; then
    err "No target device selected"
    cleanup
    exit 1
  fi

  awk '{print $1}' <<<"$selection"
}

#──────────────────────────────────────────────────────────────────────────────
# DEPENDENCY VALIDATION
#──────────────────────────────────────────────────────────────────────────────

# Check for required system dependencies
# Exits with error if any critical tools are missing
check_deps() {
  local -a deps=(
    losetup parted mkfs.f2fs mkfs.vfat rsync xz blkid
    partprobe lsblk flock awk curl wipefs udevadm
  ) missing=() cmd

  # Add shrink-specific dependencies
  ((cfg[shrink])) && deps+=(e2fsck resize2fs tune2fs truncate)

  for cmd in "${deps[@]}"; do
    has "$cmd" || missing+=("$cmd")
  done

  if ((${#missing[@]} > 0)); then
    err "Missing required dependencies: ${missing[*]}"
    err "Install: apt install ${missing[*]}"
    cleanup
    exit 1
  fi
}

#──────────────────────────────────────────────────────────────────────────────
# CLEANUP & ERROR HANDLING
#──────────────────────────────────────────────────────────────────────────────

# Comprehensive cleanup function (runs on EXIT/INT/TERM)
# Unmounts filesystems, detaches loop devices, releases locks, removes temp files
cleanup() {
  local ret=$?
  set +e # Don't fail on cleanup errors

  # Unmount in reverse order (last mounted first)
  for ((i = ${#MOUNTED_DIRS[@]} - 1; i >= 0; i--)); do
    umount -lf "${MOUNTED_DIRS[i]}" &>/dev/null
  done

  # Detach loop device
  [[ -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" &>/dev/null

  # Release file lock
  if ((LOCK_FD >= 0)); then
    exec {LOCK_FD}>&-
    LOCK_FD=-1
  fi

  # Remove lock and temp files
  [[ -f ${LOCK_FILE:-} ]] && rm -f "$LOCK_FILE"
  [[ -n ${WORKDIR:-} && -d $WORKDIR ]] && rm -rf "$WORKDIR"

  return "$ret"
}

#──────────────────────────────────────────────────────────────────────────────
# PARTITION PATH HANDLING
#──────────────────────────────────────────────────────────────────────────────

# Derive partition paths from base device
# Handles NVMe (nvme0n1p1), MMC (mmcblk0p1), loop (loop0p1), and SCSI (sda1)
# Sets global:  BOOT_PART, ROOT_PART
derive_partition_paths() {
  local dev="${1:?missing device}"
  if [[ $dev =~ nvme|mmcblk|loop ]]; then
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  fi
}

# Wait for kernel to recognize new partitions
# Uses partprobe + udevadm settle + polling loop
wait_for_partitions() {
  local dev="${1:?missing device}"
  ((cfg[dry_run])) && return 0

  # Trigger kernel partition re-read
  partprobe "$dev" &>/dev/null
  udevadm settle &>/dev/null
  sleep 1

  # Derive expected partition paths
  derive_partition_paths "$dev"

  # Poll for partition block devices (max 15 seconds)
  local i
  for ((i = 0; i < 30; i++)); do
    if [[ -b $BOOT_PART && -b $ROOT_PART ]]; then
      return 0
    fi
    sleep 0.5
  done

  err "Partitions failed to appear on $dev after 15s"
  cleanup
  exit 1
}

#──────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT PREPARATION
#──────────────────────────────────────────────────────────────────────────────

# Initialize working environment
# Creates temp directory, sets up cleanup trap, drops caches
prepare_environment() {
  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" rf2fs. XXXXXX)
  SRC_IMG="$WORKDIR/source.img"
  trap cleanup EXIT INT TERM

  # Drop OS caches for accurate I/O performance
  sync
  sudo sh -c 'echo 3>/proc/sys/vm/drop_caches' 2>/dev/null || :
}

#──────────────────────────────────────────────────────────────────────────────
# SOURCE IMAGE PROCESSING
#──────────────────────────────────────────────────────────────────────────────

# Download or prepare source image
# Supports:  local files, URLs (plain/xz), "dietpi" keyword
# Decompresses xz archives on-the-fly
process_source() {
  # Handle "dietpi" keyword
  if [[ $SRC_PATH == dietpi ]]; then
    log "Keyword 'dietpi' detected, using:  $DIETPI_URL"
    SRC_PATH="$DIETPI_URL"
  fi

  # Download from URL
  if [[ $SRC_PATH =~ ^https?:// ]]; then
    log "Downloading image from URL..."

    if [[ $SRC_PATH == *.xz ]]; then
      # Streaming decompression (saves disk space)
      curl -Lfs --progress-bar "$SRC_PATH" | xz -dc >"$SRC_IMG" || {
        err "Download/decompression failed"
        cleanup
        exit 1
      }
    else
      # Direct download
      curl -Lfs --progress-bar "$SRC_PATH" -o "$SRC_IMG" || {
        err "Download failed"
        cleanup
        exit 1
      }
    fi
    return 0
  fi

  # Process local file
  log "Processing local source:  $SRC_PATH"

  if [[ ! -f $SRC_PATH ]]; then
    err "Source file not found: $SRC_PATH"
    cleanup
    exit 1
  fi

  # Handle xz-compressed images
  if [[ $SRC_PATH == *.xz ]]; then
    log "Decompressing xz archive..."
    xz -dc "$SRC_PATH" >"$SRC_IMG"
  elif ((cfg[keep_source])); then
    # Copy (with CoW optimization)
    cp --reflink=auto "$SRC_PATH" "$SRC_IMG"
  else
    # Try hardlink (fast), fallback to copy
    ln "$SRC_PATH" "$SRC_IMG" 2>/dev/null || cp "$SRC_PATH" "$SRC_IMG"
  fi
}

#──────────────────────────────────────────────────────────────────────────────
# FILESYSTEM OPERATIONS
#──────────────────────────────────────────────────────────────────────────────

# Check and repair ext4 filesystem
# Attempts multiple recovery strategies (superblock alternates)
check_filesystem() {
  local dev="${1:?missing device}"
  log "Checking filesystem on $dev..."

  # Primary fsck (preen + force)
  e2fsck -pf "$dev"
  (($? < 4)) && return

  # Secondary fsck (automatic repair)
  warn "Filesystem errors detected, attempting repair..."
  e2fsck -y "$dev"
  (($? < 4)) && return

  # Tertiary fsck (alternate superblock)
  warn "Using alternate superblock for recovery..."
  e2fsck -fy -b 32768 "$dev"
  (($? < 4)) && return

  err "Filesystem recovery failed (continuing anyway, may lose data)"
}

#──────────────────────────────────────────────────────────────────────────────
# IMAGE SHRINKING (PiShrink-like Algorithm)
#──────────────────────────────────────────────────────────────────────────────

# Shrink source image before flashing (saves time and wear)
# Algorithm:
#   1. Find last partition (rootfs)
#   2. Check and repair filesystem
#   3. Resize filesystem to minimum + buffer
#   4. Zero free space (improves compression)
#   5. Shrink partition table
#   6. Truncate image file
shrink_source_image() {
  log "Shrinking source image (PiShrink algorithm)..."

  # Parse partition table
  local parted_out
  parted_out=$(parted -ms "$SRC_IMG" unit B print) || {
    err "parted failed (skipping shrink)"
    return
  }

  # Extract last partition info
  local partnum partstart parttype
  partnum=$(awk -F: 'END{print $1}' <<<"$parted_out")
  partstart=$(awk -F: 'END{print $2}' <<<"$parted_out" | tr -d B)

  # Detect partition type (primary vs logical)
  if parted -s "$SRC_IMG" unit B print | grep "$partstart" | grep -q logical; then
    parttype="logical"
  else
    parttype="primary"
  fi

  # Setup loop device at partition offset
  LOOP_DEV=$(losetup -f --show -o "$partstart" "$SRC_IMG") || {
    err "Failed to setup loop device (skipping shrink)"
    return
  }

  # Filesystem check and repair
  check_filesystem "$LOOP_DEV"

  # Get filesystem parameters
  local tune_out currentsize blocksize minsize
  tune_out=$(tune2fs -l "$LOOP_DEV" 2>&1) || {
    err "tune2fs failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }

  currentsize=$(awk -F: '/^Block count:/{gsub(" ","",$2);print $2}' <<<"$tune_out")
  blocksize=$(awk -F: '/^Block size:/{gsub(" ","",$2);print $2}' <<<"$tune_out")

  # Calculate minimum size
  minsize=$(resize2fs -P "$LOOP_DEV" 2>&1 | awk -F: '{gsub(" ","",$2);print $2}') || {
    err "resize2fs -P failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }

  # Check if already minimal
  if [[ $currentsize -eq $minsize ]]; then
    log "Source image already at minimum size"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  fi

  # Add safety buffer (prevents resize failures)
  local extra_space=$((currentsize - minsize))
  for space in 5000 1000 100; do
    if ((extra_space > space)); then
      minsize=$((minsize + space))
      break
    fi
  done

  # Resize filesystem
  log "Resizing filesystem to ${minsize} blocks..."
  resize2fs -p "$LOOP_DEV" "$minsize" || {
    err "resize2fs failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }

  # Zero free space (improves compression, reduces wear on flash)
  local mnt
  mnt=$(mktemp -d)
  mount "$LOOP_DEV" "$mnt"
  log "Zeroing free space (this may take a while)..."
  cat /dev/zero >"$mnt/zero_file" 2>/dev/null || :
  rm -f "$mnt/zero_file"
  umount "$mnt"
  rmdir "$mnt"

  # Calculate new partition end
  local partnewsize newpartend
  partnewsize=$((minsize * blocksize))
  newpartend=$((partstart + partnewsize))

  # Resize partition in table
  log "Shrinking partition table..."
  parted -s -a minimal "$SRC_IMG" rm "$partnum" || {
    err "parted rm failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }

  parted -s "$SRC_IMG" unit B mkpart "$parttype" "$partstart" "$newpartend" || {
    err "parted mkpart failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }

  losetup -d "$LOOP_DEV" &>/dev/null

  # Truncate image file
  local endresult
  endresult=$(parted -ms "$SRC_IMG" unit B print free | tail -1 | awk -F: '{print $2}' | tr -d B)
  log "Truncating image to ${endresult}B..."
  truncate -s "$endresult" "$SRC_IMG" || {
    err "truncate failed (non-fatal)"
    return
  }

  msg "Source image shrunk successfully (faster flash ahead)"
}

#──────────────────────────────────────────────────────────────────────────────
# TARGET DEVICE SETUP
#──────────────────────────────────────────────────────────────────────────────

# Prepare target device for flashing
# - Acquires exclusive lock (prevents concurrent access)
# - Validates device safety (USB/MMC check)
# - Creates partition table (MSDOS/MBR)
# - Creates two partitions (FAT32 boot, F2FS root)
setup_target_device() {
  log "Preparing target device:  $TGT_PATH"

  # Create device-specific lock file (sanitize path for filename)
  local lock_suffix
  lock_suffix=${TGT_PATH//\//_}
  LOCK_FILE="/run/lock/raspi-f2fs-${lock_suffix}. lock"
  mkdir -p "${LOCK_FILE%/*}"

  # Open lock file
  exec {LOCK_FD}>"$LOCK_FILE" || {
    err "Cannot create lock file"
    cleanup
    exit 1
  }

  # Acquire exclusive lock (non-blocking)
  flock -n "$LOCK_FD" || {
    err "Device $TGT_PATH is in use by another process"
    cleanup
    exit 1
  }

  # Safety validations
  assert_usb_dev "$TGT_PATH"
  assert_size "$SRC_IMG" "$TGT_PATH"

  ((cfg[dry_run])) && return 0

  # Final warning
  warn "${RED}${BLD}WARNING: ALL DATA ON $TGT_PATH WILL BE PERMANENTLY ERASED! ${DEF}"

  # Wipe existing filesystem signatures
  wipefs -af "$TGT_PATH" &>/dev/null

  # Create partition table
  log "Creating MSDOS partition table..."
  parted -s "$TGT_PATH" mklabel msdos

  # Create partitions
  # Partition 1: FAT32 boot (bootable flag set)
  # Partition 2: F2FS root (remainder of disk)
  parted -s "$TGT_PATH" mkpart primary fat32 0% "${cfg[boot_size]}"
  parted -s "$TGT_PATH" mkpart primary "${cfg[boot_size]}" 100%
  parted -s "$TGT_PATH" set 1 boot on

  # Wait for kernel to recognize partitions
  wait_for_partitions "$TGT_PATH"

  TGT_DEV="$TGT_PATH"
}

#──────────────────────────────────────────────────────────────────────────────
# FILESYSTEM FORMATTING
#──────────────────────────────────────────────────────────────────────────────

# Format boot (FAT32) and root (F2FS) partitions
# F2FS options:
#   - extra_attr: Extended attributes support
#   - inode_checksum: Inode integrity checking
#   - sb_checksum:  Superblock integrity checking
#   - compression: Transparent compression (kernel 5.6+)
format_target() {
  log "Formatting filesystems..."
  ((cfg[dry_run])) && return 0

  # Boot partition:  FAT32 (required for Raspberry Pi bootloader)
  mkfs.vfat -F32 -n BOOT "$BOOT_PART" &>/dev/null

  # Root partition: F2FS with optimizations
  mkfs.f2fs -f -l ROOT \
    -O extra_attr,inode_checksum,sb_checksum,compression \
    "$ROOT_PART" &>/dev/null
}

#──────────────────────────────────────────────────────────────────────────────
# DATA CLONING
#──────────────────────────────────────────────────────────────────────────────

# Clone data from source image to target device
# Uses rsync for efficient file-level copying with:
#   - Archive mode (-a): preserves permissions, timestamps, etc.
#   - Hard links (-H): preserves hard link relationships
#   - ACLs (-A): preserves access control lists
#   - Extended attributes (-X): preserves xattrs
clone_data() {
  log "Cloning data (this may take several minutes)..."
  ((cfg[dry_run])) && return 0

  # Setup loop device for source image
  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")
  derive_partition_paths "$LOOP_DEV"

  # Create mount points
  mkdir -p "$WORKDIR"/{src,tgt}/{boot,root}

  # Mount source partitions (read-only)
  mount -o ro "$BOOT_PART" "$WORKDIR/src/boot"
  MOUNTED_DIRS+=("$WORKDIR/src/boot")

  mount -o ro "$ROOT_PART" "$WORKDIR/src/root"
  MOUNTED_DIRS+=("$WORKDIR/src/root")

  # Mount target partitions (read-write)
  derive_partition_paths "$TGT_DEV"

  mount "$BOOT_PART" "$WORKDIR/tgt/boot"
  MOUNTED_DIRS+=("$WORKDIR/tgt/boot")

  mount "$ROOT_PART" "$WORKDIR/tgt/root"
  MOUNTED_DIRS+=("$WORKDIR/tgt/root")

  # Sync boot partition
  log "Syncing /boot partition..."
  rsync -aHAX --info=progress2 \
    "$WORKDIR/src/boot/" "$WORKDIR/tgt/boot/"

  # Sync root partition (exclude lost+found)
  log "Syncing / (rootfs) - this is the longest step..."
  rsync -aHAX --info=progress2 \
    --exclude 'lost+found' \
    "$WORKDIR/src/root/" "$WORKDIR/tgt/root/"

  # Ensure all data is written to disk
  sync
}

#──────────────────────────────────────────────────────────────────────────────
# BOOT CONFIGURATION
#──────────────────────────────────────────────────────────────────────────────

# Configure Raspberry Pi boot parameters for F2FS
# Modifies:
#   - cmdline.txt: kernel boot parameters (root device, fstype)
#   - /etc/fstab: filesystem mount table
#   - /boot/ssh: SSH enablement (if -s flag)
configure_pi_boot() {
  log "Configuring F2FS boot parameters..."
  ((cfg[dry_run])) && return 0

  # Get partition UUIDs (PARTUUID is more reliable than UUID)
  local boot_uuid root_uuid
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")

  local cmdline fstab
  cmdline="$WORKDIR/tgt/boot/cmdline.txt"
  fstab="$WORKDIR/tgt/root/etc/fstab"

  # Update cmdline.txt
  # - Change root= to use PARTUUID
  # - Change rootfstype= to f2fs
  # - Remove init=/usr/lib/raspberrypi-sys-mods/init_resize.sh (not needed)
  awk -v uuid="$root_uuid" '{
    line="";
    for(i=1; i<=NF; i++){
      if($i ~ /^root=/)
        $i="root=PARTUUID="uuid;
      else if($i ~ /^rootfstype=/)
        $i="rootfstype=f2fs";
      else if($i ~ /^init=.*init_resize\. sh/)
        continue;
      line=(line ?  line" "$i :  $i)
    }
    print line
  }' "$cmdline" >"${cmdline}.new"
  mv "${cmdline}. new" "$cmdline"

  # Regenerate fstab
  cat >"$fstab" <<-EOF
	# Raspberry Pi F2FS Configuration
	# Generated by raspi-f2fs. sh on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
	
	proc            /proc           proc    defaults          0       0
	PARTUUID=$boot_uuid  /boot           vfat    defaults          0       2
	PARTUUID=$root_uuid  /               f2fs    defaults,noatime  0       1
	EOF

  # Enable SSH if requested
  if ((cfg[ssh])); then
    log "Enabling SSH on first boot..."
    touch "$WORKDIR/tgt/boot/ssh"
  fi

  log "Boot configuration complete"
}

#──────────────────────────────────────────────────────────────────────────────
# USAGE & CLI PARSING
#──────────────────────────────────────────────────────────────────────────────

usage() {
  cat <<-'EOF'
	━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
	  raspi-f2fs.sh - Raspberry Pi F2FS Flasher
	━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
	
	Flash Raspberry Pi images to SD cards with F2FS root filesystem for improved
	performance and longevity on flash media.
	
	USAGE: 
	  sudo ./raspi-f2fs. sh [OPTIONS]
	
	OPTIONS:
	  -i FILE|URL     Source image (. img, .img.xz, URL, or 'dietpi')
	  -d DEVICE       Target device (e.g., /dev/sdb)
	  -b SIZE         Boot partition size (default: 512M)
	  -z              Shrink source image before flash (PiShrink algorithm)
	  -s              Enable SSH on first boot
	  -k              Keep extracted source files (don't delete)
	  -U              Disable USB/MMC safety check (DANGEROUS)
	  -F              Disable size validation check
	  -n              Dry-run mode (no actual writes)
	  -h              Show this help message
	
	EXAMPLES:
	  # Interactive mode (prompts for source and target)
	  sudo ./raspi-f2fs.sh
	
	  # Flash DietPi with SSH enabled
	  sudo ./raspi-f2fs.sh -i dietpi -d /dev/sdb -s
	
	  # Flash from URL with shrinking (recommended)
	  sudo ./raspi-f2fs.sh -i https://example.com/image.img.xz -d /dev/sdc -z
	
	  # Flash local image with custom boot partition size
	  sudo ./raspi-f2fs.sh -i raspios. img -d /dev/sdd -b 1024M
	
	SUPPORTED SOURCES:
	  - Local . img files (raw or xz-compressed)
	  - HTTP/HTTPS URLs (raw or xz-compressed)
	  - Special keyword "dietpi" (downloads latest DietPi)
	
	SAFETY FEATURES:
	  - USB/MMC device detection (prevents internal drive overwrites)
	  - Size validation (prevents truncated images)
	  - Exclusive device locking (prevents concurrent operations)
	  - Comprehensive error handling and cleanup
	
	REQUIREMENTS:
	  - Root privileges (sudo)
	  - Kernel with F2FS support (CONFIG_F2FS_FS=y/m)
	  - f2fs-tools, rsync, parted, xz-utils
	  - Optional: fzf (for interactive device selection)
	
	NOTES:
	  - DESTRUCTIVE: All data on target device will be permanently erased
	  - F2FS requires kernel 3.8+ (Raspberry Pi OS has it built-in)
	  - Shrinking (-z) can save significant time on slow SD cards
	  - Use DEBUG=1 environment variable for verbose logging
	
	━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
	EOF
  exit 0
}

# CLI argument parsing
while getopts "b:i:d:zsknhUF" opt; do
  case $opt in
    b) cfg[boot_size]=$OPTARG ;;
    i) SRC_PATH=$OPTARG ;;
    d) TGT_PATH=$OPTARG ;;
    z) cfg[shrink]=1 ;;
    s) cfg[ssh]=1 ;;
    k) cfg[keep_source]=1 ;;
    n) cfg[dry_run]=1 ;;
    U) cfg[no_usb_check]=1 ;;
    F) cfg[no_size_check]=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

#──────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION FLOW
#──────────────────────────────────────────────────────────────────────────────

# Root privilege check
if [[ $EUID -ne 0 ]]; then
  err "This script requires root privileges"
  err "Run with:  sudo $0 $*"
  cleanup
  exit 1
fi

# Dependency validation
check_deps

# Interactive source selection (if not specified)
if [[ -z $SRC_PATH ]]; then
  log "No source specified, entering interactive mode..."

  # Try to find local images
  SRC_PATH=$(
    find . -maxdepth 2 \( -name "*.img*" -o -name "*.xz" \) 2>/dev/null \
      | fzf --prompt="Select Source Image (or type URL/dietpi)> " \
        --print-query \
        --preview='file {}; echo; ls -lh {}' \
        --preview-window=right:50%
  )

  if [[ -z $SRC_PATH ]]; then
    err "No source image selected"
    cleanup
    exit 1
  fi
fi

# Interactive target selection (if not specified)
[[ -z $TGT_PATH ]] && TGT_PATH=$(select_target_interactive)

# Main processing pipeline
prepare_environment
process_source
((cfg[shrink])) && shrink_source_image
setup_target_device
format_target
clone_data
configure_pi_boot

# Success message
msg "${GRN}${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${DEF}"
msg "${GRN}${BLD}SUCCESS: Raspberry Pi image flashed to $TGT_PATH with F2FS root${DEF}"
msg "${GRN}${BLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${DEF}"
msg "Boot partition:  FAT32 ($BOOT_PART)"
msg "Root partition: F2FS ($ROOT_PART)"
((cfg[ssh])) && msg "SSH: Enabled on first boot"
msg ""
msg "You can now safely eject and boot the device"
msg "First boot may take longer due to filesystem initialization"
