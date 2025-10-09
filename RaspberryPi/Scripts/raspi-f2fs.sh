#!/usr/bin/env bash
# raspi-f2fs.sh - Flash Raspberry Pi images to SD cards with F2FS root filesystem
# 
# Features:
# - Converts Raspberry Pi OS images from ext4 to F2FS for better flash performance
# - Works with both physical devices (/dev/sdX) and image files (output.img)
# - Interactive mode for source/target selection with fzf
# - Optional SSH enablement on first boot
# - First-boot auto-resize for F2FS partitions
# - Optimized for both speed and safety
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C

# --- Config ---
BOOT_SIZE="512M"  # FAT32 boot partition size
DRY_RUN=0
DEBUG=0
ENABLE_SSH=0
SOURCE_PATH=""
TARGET_PATH=""
KEEP_SOURCE=0

# --- Exit codes ---
E_USAGE=64
E_DEPEND=65
E_ABORT=130

# --- Help text ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SOURCE.img|.xz] [TARGET_DEV|TARGET.img]

  Flash Raspberry Pi images to SD cards with F2FS root filesystem for
  improved performance and flash longevity.

Options:
  -b SIZE     Boot partition size (default: $BOOT_SIZE)
  -i PATH     Source image (.img or .img.xz)
  -d DEV      Target device (e.g., /dev/sdX) or output image file
  -s          Enable SSH on first boot
  -k          Keep source image unmodified (use temp copy)
  -n          Dry-run (print commands without executing)
  -x          Enable debug output
  -h          Show this help

Examples:
  $(basename "$0") -i 2023-12-05-raspios.img -d /dev/sdb -s
  $(basename "$0") -b 1G 2023-12-05-raspios.img.xz output.img
EOF
  exit "$E_USAGE"
}

# --- Logging ---
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }
log_info() { log "INFO: $1"; }
log_warn() { log "WARN: $1" >&2; }
log_error() { log "ERROR: $1" >&2; }
log_debug() { [[ $DEBUG -eq 1 ]] && log "DEBUG: $1"; }

# --- Dependencies ---
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "Required command \"$1\" not found. Please install it."
    case "$1" in
      fzf) log_error "Arch: pacman -S fzf | Debian: apt install fzf | Termux: pkg install fzf" ;;
      mkfs.f2fs) log_error "Arch: pacman -S f2fs-tools | Debian: apt install f2fs-tools" ;;
      losetup) log_error "Arch: pacman -S util-linux | Debian: apt install util-linux" ;;
    esac
    exit "$E_DEPEND"
  }
}

# --- Helper functions ---
check_deps() {
  for cmd in losetup parted mkfs.f2fs mkfs.vfat rsync tar xz curl blkid blockdev; do
    require_cmd "$cmd"
  done
  
  # Optional deps for interactive mode
  [[ -z $SOURCE_PATH && -z $TARGET_PATH ]] && require_cmd fzf
}

fzf_file_picker() {
  require_cmd fzf
  if command -v fd >/dev/null 2>&1; then
    fd -tf -e img -e xz -p "${HOME:-.}" \
      | fzf --height=~40% --layout=reverse --inline-info \
            --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  else
    find "${HOME:-.}" -type f \( -iname '*.img' -o -iname '*.xz' \) -print0 2>/dev/null \
      | fzf --read0 --height=~40% --layout=reverse --inline-info \
            --prompt="Select image: " \
            --header="Select image (.img,.xz)" \
            --preview='file --mime-type {} 2>/dev/null || ls -lh {}' \
            --preview-window=right:50%:wrap --no-multi -1 -0
  fi
}

fzf_device_picker() {
  require_cmd fzf
  lsblk -dnp -o NAME,TYPE,RM,SIZE,MODEL,MOUNTPOINT \
    | awk '$2=="disk" && ($3=="1" || $3=="0") && ($6=="" || $6=="-") {printf "%s\t%s %s\n",$1,$4,$5}' \
    | fzf --height=~40% --layout=reverse --inline-info \
          --prompt="Select target device: " \
          --header="⚠️  DEVICE WILL BE WIPED ⚠️\nPath\tSize Model" \
          --no-multi -1 -0 \
    | awk '{print $1}'
}

run() {
  # Execute a command, honouring dry‑run mode
  if (( DRY_RUN )); then
    log_info "[dry‑run] $*"
  else
    eval "$*"
  fi
}

# --- Main functionality ---
prepare_workdir() {
  WORKDIR="$(mktemp -d)"
  SRC_IMG="${WORKDIR}/source.img"
  BOOT_MNT="${WORKDIR}/boot"
  ROOT_MNT="${WORKDIR}/root"
  
  mkdir -p -- "$BOOT_MNT" "$ROOT_MNT"
  
  # Make sure we clean up on exit
  cleanup() {
    log_debug "Cleaning up..."
    umount -q "$BOOT_MNT" 2>/dev/null || true
    umount -q "$ROOT_MNT" 2>/dev/null || true
    if [[ -n "${LOOP_DEV:-}" ]]; then
      losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    if [[ -n "${TARGET_LOOP:-}" ]]; then
      losetup -d "$TARGET_LOOP" 2>/dev/null || true
    fi
    [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
    log_debug "Cleanup complete"
  }
  trap cleanup EXIT
}

prepare_source() {
  log_info "Preparing source image..."
  
  # Handle remote URLs
  case "$SOURCE_PATH" in
    http://*|https://*)
      log_info "Downloading $SOURCE_PATH"
      SRC_URL="$SOURCE_PATH"
      SOURCE_PATH="${WORKDIR}/$(basename "$SRC_URL")"
      curl -C - -SfL --progress-bar -o "$SOURCE_PATH" "$SRC_URL"
      ;;
  esac

  # Extract compressed files or copy source
  case "$SOURCE_PATH" in
    *.xz)  
      log_info "Extracting XZ compressed image..."
      xz -dc "$SOURCE_PATH" > "$SRC_IMG" 
      ;;
    *)
      if [[ $KEEP_SOURCE -eq 1 ]]; then
        log_info "Copying source image..."
        cp --reflink=auto "$SOURCE_PATH" "$SRC_IMG"
      else
        log_info "Using source image directly..."
        SRC_IMG="$SOURCE_PATH"
      fi
      ;;
  esac
  
  if [[ ! -f "$SRC_IMG" ]]; then
    log_error "Source image not found or invalid: $SOURCE_PATH"
    exit 1
  fi
  
  log_debug "Source ready: $SRC_IMG"
}

prepare_target() {
  local target="$1"
  
  if [[ -b "$target" ]]; then
    log_info "Target is block device: $target"
    # Confirm destructive operation
    if [[ $DRY_RUN -eq 0 ]]; then
      log_warn "[*] WARNING: All data on ${target} will be DESTROYED!"
      local confirm
      read -r -p "Type YES in uppercase to continue: " confirm
      [[ "$confirm" != "YES" ]] && { log_info "Aborted by user."; exit "$E_ABORT"; }
    fi
    TARGET_DEV="$target"
    IS_BLOCK_DEVICE=1
  else
    log_info "Target is image file: $target"
    log_info "Creating empty image file..."
    
    # Determine size needed for the output image
    local source_size_mb=$(du -m "$SRC_IMG" | cut -f1)
    local target_size_mb=$((source_size_mb + 200))  # Add 200MB buffer
    
    run "truncate -s ${target_size_mb}M \"$target\""
    
    # Set up loop device for the target image
    if [[ $DRY_RUN -eq 0 ]]; then
      TARGET_LOOP=$(losetup --show -f -P "$target")
      TARGET_DEV="$TARGET_LOOP"
    else
      TARGET_DEV="(loop-device)"
      TARGET_LOOP="(loop-device)"
    fi
    IS_BLOCK_DEVICE=0
  fi
  
  # Determine partition names based on device type
  case "$TARGET_DEV" in
    *mmcblk*|*nvme*) 
      PART_BOOT="${TARGET_DEV}p1"; PART_ROOT="${TARGET_DEV}p2" 
      ;;
    *)              
      PART_BOOT="${TARGET_DEV}1";  PART_ROOT="${TARGET_DEV}2"  
      ;;
  esac
  
  log_debug "Target device: $TARGET_DEV"
  log_debug "Boot partition: $PART_BOOT"
  log_debug "Root partition: $PART_ROOT"
}

partition_target() {
  log_info "Partitioning target device..."
  
  # Wipe existing partition table
  run "wipefs -af \"$TARGET_DEV\""
  
  # Create new partition table and partitions
  run "parted -s \"$TARGET_DEV\" mklabel msdos"
  run "parted -s \"$TARGET_DEV\" mkpart primary fat32 0% $BOOT_SIZE"
  run "parted -s \"$TARGET_DEV\" mkpart primary $BOOT_SIZE 100%"
  run "partprobe \"$TARGET_DEV\""
  
  # Give udev time to create device nodes if needed
  if [[ $DRY_RUN -eq 0 ]]; then
    udevadm settle || sleep 2
  fi
  
  # Create filesystems
  log_info "Creating filesystems..."
  run "mkfs.vfat -F32 -I -n boot \"$PART_BOOT\""
  run "mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l root \"$PART_ROOT\""
}

mount_source_image() {
  log_info "Mounting source image partitions..."
  
  # Detect loop-device suffix
  if [[ $DRY_RUN -eq 0 ]]; then
    LOOP_DEV=$(losetup --show -fP "$SRC_IMG")
    log_debug "Source loop device: $LOOP_DEV"
    
    # Some loop devices need a "p" suffix, others don't
    local p1=""
    if [[ -b "${LOOP_DEV}p1" ]]; then
      p1="${LOOP_DEV}p1"
      p2="${LOOP_DEV}p2"
    else
      p1="${LOOP_DEV}1"
      p2="${LOOP_DEV}2"
    fi
    
    # Mount source partitions
    run "mount \"$p1\" \"$BOOT_MNT\""
    run "mount \"$p2\" \"$ROOT_MNT\""
  else
    LOOP_DEV="(loop-device)"
    log_info "[dry-run] Would mount source partitions"
  fi
}

mount_target_partitions() {
  log_info "Mounting target partitions..."
  
  TARGET_BOOT="${WORKDIR}/target_boot"
  TARGET_ROOT="${WORKDIR}/target_root"
  mkdir -p "$TARGET_BOOT" "$TARGET_ROOT"
  
  if [[ $DRY_RUN -eq 0 ]]; then
    run "mount \"$PART_BOOT\" \"$TARGET_BOOT\""
    run "mount \"$PART_ROOT\" \"$TARGET_ROOT\""
  fi
}

copy_boot_partition() {
  log_info "Copying boot partition..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    # Try to use tmpfs for speed if enough RAM is available
    local root_size_mb=$(du -sm "$BOOT_MNT" | awk '{print $1}')
    local tmpfs_size_mb=$((root_size_mb + 50))  # Add 50MB buffer
    local free_mb=$(free -m | awk '/Mem:/ {print $7}')
    
    if [[ $free_mb -ge $((tmpfs_size_mb * 2)) ]]; then
      log_info "Using RAM for faster copy..."
      local tmpfs_mnt="${WORKDIR}/tmpfs_boot"
      mkdir -p "$tmpfs_mnt"
      mount -t tmpfs -o size="${tmpfs_size_mb}M" tmpfs "$tmpfs_mnt"
      
      # Fast copy via tar through tmpfs
      (cd "$BOOT_MNT" && tar -cpf - .) | (cd "$tmpfs_mnt" && tar -xpf -)
      (cd "$tmpfs_mnt" && tar -cpf - .) | (cd "$TARGET_BOOT" && tar -xpf -)
      
      umount "$tmpfs_mnt"
      rm -rf "$tmpfs_mnt"
    else
      log_info "Using direct copy method..."
      rsync -aHAX --info=progress2 "$BOOT_MNT/" "$TARGET_BOOT/"
    fi
  else
    log_info "[dry-run] Would copy boot partition"
  fi
}

copy_root_partition() {
  log_info "Copying root partition..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    # Try to use tmpfs for speed if enough RAM is available
    local root_size_mb=$(du -sm "$ROOT_MNT" | awk '{print $1}')
    local tmpfs_size_mb=$((root_size_mb + 100))  # Add 100MB buffer
    local free_mb=$(free -m | awk '/Mem:/ {print $7}')
    
    if [[ $free_mb -ge $((tmpfs_size_mb * 2)) ]]; then
      log_info "Using RAM for faster copy..."
      local tmpfs_mnt="${WORKDIR}/tmpfs_root"
      mkdir -p "$tmpfs_mnt"
      mount -t tmpfs -o size="${tmpfs_size_mb}M" tmpfs "$tmpfs_mnt"
      
      # Fast copy via tar through tmpfs
      (cd "$ROOT_MNT" && tar -cpf - .) | (cd "$tmpfs_mnt" && tar -xpf -)
      (cd "$tmpfs_mnt" && tar -cpf - .) | (cd "$TARGET_ROOT" && tar -xpf -)
      
      umount "$tmpfs_mnt"
      rm -rf "$tmpfs_mnt"
    else
      log_info "Using direct copy method..."
      rsync -aHAX --info=progress2 "$ROOT_MNT/" "$TARGET_ROOT/"
    fi
  else
    log_info "[dry-run] Would copy root partition"
  fi
}

update_config_files() {
  log_info "Updating configuration files for F2FS..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    # Get partition UUIDs
    local boot_uuid=$(blkid -s PARTUUID -o value "$PART_BOOT")
    local root_uuid=$(blkid -s PARTUUID -o value "$PART_ROOT")
    
    # Update cmdline.txt
    if [[ -f "${TARGET_BOOT}/cmdline.txt" ]]; then
      log_debug "Updating cmdline.txt"
      sed -i "s|root=[^ ]*|root=PARTUUID=$root_uuid|" "${TARGET_BOOT}/cmdline.txt"
      sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "${TARGET_BOOT}/cmdline.txt"
      # Remove resize script if present
      sed -i 's| init=/usr/lib/raspi-config/init_resize.sh||' "${TARGET_BOOT}/cmdline.txt"
    fi
    
    # Update fstab
    log_debug "Creating new fstab"
    cat > "${TARGET_ROOT}/etc/fstab" <<EOF
proc                  /proc   proc    defaults                    0   0
PARTUUID=$boot_uuid  /boot   vfat    defaults                    0   2
PARTUUID=$root_uuid  /       f2fs    defaults,noatime,discard    0   1
EOF
  else
    log_info "[dry-run] Would update configuration files"
  fi
}

setup_first_boot() {
  log_info "Setting up first-boot configurations..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    # Create F2FS resize script
    mkdir -p "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount"
    cat > "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize" <<'EOF'
#!/bin/sh
. /scripts/functions
log_begin_msg "Expanding F2FS root filesystem..."
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -x /sbin/resize.f2fs ]; then
  /sbin/resize.f2fs "$ROOT_DEV"
  log_end_msg "F2FS root filesystem expanded."
  rm -f /etc/initramfs-tools/scripts/init-premount/f2fsresize
else
  log_end_msg "resize.f2fs not found – skipping."
fi
EOF
    chmod +x "${TARGET_ROOT}/etc/initramfs-tools/scripts/init-premount/f2fsresize"
    
    # Enable SSH if requested
    if [[ $ENABLE_SSH -eq 1 ]]; then
      log_info "Enabling SSH on first boot"
      touch "${TARGET_BOOT}/ssh"
    fi
  else
    log_info "[dry-run] Would set up first-boot configurations"
    [[ $ENABLE_SSH -eq 1 ]] && log_info "[dry-run] Would enable SSH"
  fi
}

finalize() {
  log_info "Finalizing and syncing..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    sync
    
    # Final checks
    if [[ -b "$PART_BOOT" && -b "$PART_ROOT" ]]; then
      log_info "Verifying partition sizes:"
      df -h "$PART_BOOT" "$PART_ROOT" || true
    fi
  fi
  
  log_info "Process complete!"
  if [[ $IS_BLOCK_DEVICE -eq 1 ]]; then
    log_info "SD card '$TARGET_DEV' is ready for use."
  else
    log_info "Image file '$TARGET_PATH' is ready for use."
  fi
}

main() {
  # Parse arguments
  while getopts "b:i:d:sknxh" opt; do
    case "$opt" in
      b) BOOT_SIZE="$OPTARG" ;;
      i) SOURCE_PATH="$OPTARG" ;;
      d) TARGET_PATH="$OPTARG" ;;
      s) ENABLE_SSH=1 ;;
      k) KEEP_SOURCE=1 ;;
      n) DRY_RUN=1 ;;
      x) DEBUG=1; set -x ;;
      h|?) usage ;;
    esac
  done
  shift $((OPTIND-1))
  
  # Get positional arguments if not provided as options
  [[ -z $SOURCE_PATH && $# -ge 1 ]] && SOURCE_PATH="$1" && shift
  [[ -z $TARGET_PATH && $# -ge 1 ]] && TARGET_PATH="$1" && shift
  
  # Verify dependencies
  check_deps
  
  # Interactive mode if source or target not provided
  if [[ -z $SOURCE_PATH ]]; then
    log_info "No source specified, entering interactive selection mode"
    SOURCE_PATH="$(fzf_file_picker)"
    [[ -z $SOURCE_PATH ]] && { log_error "No source selected"; exit "$E_USAGE"; }
  fi
  
  if [[ -z $TARGET_PATH ]]; then
    log_info "No target specified, entering interactive selection mode"
    TARGET_PATH="$(fzf_device_picker)"
    [[ -z $TARGET_PATH ]] && { log_error "No target selected"; exit "$E_USAGE"; }
  fi
  
  log_info "Starting Raspberry Pi F2FS conversion..."
  log_info "Source: $SOURCE_PATH"
  log_info "Target: $TARGET_PATH"
  log_info "Boot size: $BOOT_SIZE"
  [[ $ENABLE_SSH -eq 1 ]] && log_info "SSH will be enabled on first boot"
  
  # Execute the conversion process
  prepare_workdir
  prepare_source
  prepare_target "$TARGET_PATH"
  partition_target
  mount_source_image
  mount_target_partitions
  copy_boot_partition
  copy_root_partition
  update_config_files
  setup_first_boot
  finalize
}

main "$@"
