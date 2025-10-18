#!/usr/bin/env bash
# raspi-f2fs.sh - Flash Raspberry Pi images with F2FS root filesystem
set -euo pipefail
IFS=$'\n\t'

# Config
declare -A cfg=(
  [boot_size]="512M"
  [ssh]=0
  [dry_run]=0
  [debug]=0
  [keep_source]=0
)
declare src_path=""
declare tgt_path=""
declare IS_BLOCK=0
declare SRC_IMG=""
declare WORKDIR=""
declare LOOP_DEV=""
declare TGT_DEV=""
declare TGT_LOOP=""
declare BOOT_PART=""
declare ROOT_PART=""

# Logging functions
log() { printf '[%s] %s\n' "$(date +%T)" "${1-}"; }
info() { log "INFO: $1"; }
warn() { log "WARN: $1" >&2; }
error() { log "ERROR: $1" >&2; exit 1; }
debug() { ((cfg[debug])) && log "DEBUG: $1"; }

# Execute command respecting dry-run
run() {
  if ((cfg[dry_run])); then
    info "[DRY] $*"
    return 0
  fi
  debug "Run: $*"
  # Avoid eval by using arrays for command execution
  local cmd=("$@")
  "${cmd[@]}"
}

# Setup working directory
prepare() {
  info "Setting up workspace"

  WORKDIR=$(mktemp -d)
  SRC_IMG="${WORKDIR}/source.img"
  mkdir -p "${WORKDIR}"/{boot,root,target_boot,target_root}

  trap cleanup EXIT INT TERM
}

# Clean up resources
cleanup() {
  debug "Cleaning up"

  # Use arrays for directory list
  local -a dirs=(
    "${WORKDIR}/boot"
    "${WORKDIR}/root"
    "${WORKDIR}/target_boot"
    "${WORKDIR}/target_root"
  )

  # Unmount everything
  local dir
  for dir in "${dirs[@]}"; do
    mountpoint -q "$dir" >/dev/null 2>&1 && umount "$dir" >/dev/null 2>&1 || true
  done

  # Detach loop devices
  [[ -n ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" >/dev/null 2>&1 || true
  [[ -n ${TGT_LOOP:-} ]] && losetup -d "$TGT_LOOP" >/dev/null 2>&1 || true

  # Remove temp directory
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"

  debug "Cleanup complete"
}

# Check required dependencies
check_deps() {
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync tar curl blkid)
  local cmd

  for cmd in "${deps[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 ||
      error "$cmd not found. Install dependencies first."
  done

  # Only check for fzf if needed for interactive mode
  if [[ -z $src_path || -z $tgt_path ]]; then
    command -v fzf >/dev/null 2>&1 ||
      error "fzf required for interactive mode"
  fi
}

# Process source image
process_source() {
  info "Processing source: $src_path"

  case "$src_path" in
    *.xz)
      info "Extracting compressed image"
      xz -dc "$src_path" > "$SRC_IMG"
      ;;
    *)
      if ((cfg[keep_source])); then
        info "Copying source image"
        cp --reflink=auto "$src_path" "$SRC_IMG"
      else
        info "Using source directly"
        SRC_IMG="$src_path"
      fi
      ;;
  esac

  [[ -f $SRC_IMG ]] || error "Source image not found: $src_path"
}

# Configure target device or image
setup_target() {
  info "Setting up target: $tgt_path"

  if [[ -b $tgt_path ]]; then
    info "Target is block device"
    IS_BLOCK=1

    if ((cfg[dry_run]==0)); then
      warn "WARNING: All data on $tgt_path will be DESTROYED!"
      read -r -p "Type YES to continue: " confirm
      [[ $confirm == YES ]] || error "Operation aborted"
    fi

    TGT_DEV="$tgt_path"
  else
    info "Target is image file"

    # Size target image
    local size_mb
    size_mb=$(du -m "$SRC_IMG" | cut -f1)
    size_mb=$((size_mb + 200))

    info "Creating ${size_mb}MB image file"
    run truncate -s "${size_mb}M" "$tgt_path"

    if ((cfg[dry_run]==0)); then
      TGT_LOOP=$(losetup --show -f -P "$tgt_path")
      TGT_DEV="$TGT_LOOP"
      debug "Target loop: $TGT_LOOP"
    else
      TGT_DEV="loop-dev"
    fi
  fi

  # Set partition naming scheme based on device type
  case "$TGT_DEV" in
    *nvme*|*mmcblk*|*loop*)
      BOOT_PART="${TGT_DEV}p1"
      ROOT_PART="${TGT_DEV}p2"
      ;;
    *)
      BOOT_PART="${TGT_DEV}1"
      ROOT_PART="${TGT_DEV}2"
      ;;
  esac
}

# Create partitions and filesystems
partition_target() {
  info "Partitioning target device"

  run wipefs -af "$TGT_DEV"
  run parted -s "$TGT_DEV" mklabel msdos
  run parted -s "$TGT_DEV" mkpart primary fat32 0% "${cfg[boot_size]}"
  run parted -s "$TGT_DEV" mkpart primary "${cfg[boot_size]}" 100%

  if ((cfg[dry_run]==0)); then
    partprobe "$TGT_DEV" >/dev/null 2>&1 || true
    udevadm settle >/dev/null 2>&1 || sleep 2

    # Wait for devices
    local i
    for ((i=0; i<10; i++)); do
      [[ -b $BOOT_PART && -b $ROOT_PART ]] && break
      sleep 1
    done

    [[ -b $BOOT_PART && -b $ROOT_PART ]] ||
      error "Partition devices not available after waiting"
  fi

  info "Creating filesystems"
  run mkfs.vfat -F32 -I -n BOOT "$BOOT_PART"
  run mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l ROOT "$ROOT_PART"
}

# Mount source and target partitions
mount_all() {
  info "Mounting filesystems"

  if ((cfg[dry_run])); then
    info "[DRY] Would mount filesystems"
    return 0
  fi

  # Mount source
  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")
  debug "Source loop: $LOOP_DEV"

  # Detect partition scheme
  local p1 p2
  if [[ -b ${LOOP_DEV}p1 ]]; then
    p1="${LOOP_DEV}p1"
    p2="${LOOP_DEV}p2"
  else
    p1="${LOOP_DEV}1"
    p2="${LOOP_DEV}2"
  fi

  # Wait for partitions
  local i
  for ((i=0; i<5; i++)); do
    [[ -b $p1 && -b $p2 ]] && break
    sleep 1
  done
  [[ -b $p1 && -b $p2 ]] || error "Source partitions not found"

  # Mount all partitions
  mount "$p1" "${WORKDIR}/boot"
  mount "$p2" "${WORKDIR}/root"
  mount "$BOOT_PART" "${WORKDIR}/target_boot"
  mount "$ROOT_PART" "${WORKDIR}/target_root"
}

# Copy data from source to target
copy_data() {
  info "Copying data to target"
  ((cfg[dry_run])) && return 0

  # Helper function to copy with either tar or rsync
  copy_dir() {
    local src="$1" dst="$2" label="$3"
    local size_mb free_mb

    size_mb=$(du -sm "$src" | cut -f1)
    free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)

    if ((free_mb >= (size_mb*2) && size_mb > 10)); then
      info "Using RAM buffer for $label (${size_mb}MB)"
      (cd "$src" && tar -c .) | (cd "$dst" && tar -x)
    else
      info "Using direct copy for $label"
      rsync -aHAX --info=progress2 "$src/" "$dst/"
    fi
  }

  copy_dir "${WORKDIR}/boot" "${WORKDIR}/target_boot" "boot"
  copy_dir "${WORKDIR}/root" "${WORKDIR}/target_root" "root"
}

# Update configuration for F2FS
update_config() {
  info "Updating configuration for F2FS"
  ((cfg[dry_run])) && return 0

  # Get UUIDs
  local boot_uuid root_uuid
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")

  # Update cmdline.txt if exists
  local cmdline="${WORKDIR}/target_boot/cmdline.txt"
  if [[ -f $cmdline ]]; then
    debug "Updating cmdline.txt"
    sed -i "s|root=[^ ]*|root=PARTUUID=$root_uuid|" "$cmdline"
    sed -i "s|rootfstype=[^ ]*|rootfstype=f2fs|" "$cmdline"
    sed -i 's| init=/usr/lib/raspi-config/init_resize.sh||' "$cmdline"
  fi

  # Create fstab with heredoc
  cat > "${WORKDIR}/target_root/etc/fstab" <<EOF
proc                 /proc  proc   defaults           0 0
PARTUUID=$boot_uuid  /boot  vfat   defaults           0 2
PARTUUID=$root_uuid  /      f2fs   noatime,discard    0 1
EOF
}

# Setup first boot configuration
setup_boot() {
  info "Setting up first boot"
  ((cfg[dry_run])) && return 0

  # Create resize script
  local resize_dir="${WORKDIR}/target_root/etc/initramfs-tools/scripts/init-premount"
  mkdir -p "$resize_dir"

  # Use heredoc for script content
  cat > "${resize_dir}/f2fsresize" <<'EOF'
#!/bin/sh
. /scripts/functions
log_begin_msg "Expanding F2FS root filesystem..."
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -x /sbin/resize.f2fs ]; then
  /sbin/resize.f2fs "$ROOT_DEV"
  log_end_msg "F2FS filesystem expanded"
  rm -f "$0"
else
  log_end_msg "resize.f2fs not found - skipping"
fi
EOF
  chmod +x "${resize_dir}/f2fsresize"

  # Enable SSH if requested
  if ((cfg[ssh])); then
    info "Enabling SSH on first boot"
    touch "${WORKDIR}/target_boot/ssh"
  fi
}

# Complete the process
finalize() {
  info "Finalizing"

  if ((cfg[dry_run]==0)); then
    sync
    if [[ -b $BOOT_PART && -b $ROOT_PART ]]; then
      df -h "$BOOT_PART" "$ROOT_PART" >/dev/null 2>&1 || true
    fi
  fi

  info "Process complete!"
  if ((IS_BLOCK)); then
    info "SD card '$tgt_path' ready for use"
  else
    info "Image '$tgt_path' ready for use"
  fi
}

# Show usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SOURCE] [TARGET]

OPTIONS:
  -b SIZE   Boot partition size (default: ${cfg[boot_size]})
  -i FILE   Source image (.img or .img.xz)
  -d DEV    Target device (/dev/sdX) or output file
  -s        Enable SSH on first boot
  -k        Keep source (make temp copy)
  -n        Dry run
  -x        Debug
  -h        Help
EOF
  exit 0
}

# Main function
main() {
  # Parse args
  while getopts "b:i:d:sknxh" opt; do
    case "$opt" in
      b) cfg[boot_size]="$OPTARG" ;;
      i) src_path="$OPTARG" ;;
      d) tgt_path="$OPTARG" ;;
      s) cfg[ssh]=1 ;;
      k) cfg[keep_source]=1 ;;
      n) cfg[dry_run]=1 ;;
      x) cfg[debug]=1; set -x ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND-1))

  # Handle positional args
  [[ -z $src_path && $# -ge 1 ]] && src_path="$1" && shift
  [[ -z $tgt_path && $# -ge 1 ]] && tgt_path="$1" && shift

  check_deps

  # Interactive mode if needed
  if [[ -z $src_path ]]; then
    info "Interactive source selection"
    # Prefer fd (Rust tool) if available
    if command -v fd >/dev/null 2>&1; then
      src_path=$(fd -e img -e img.xz . "$HOME" | fzf --prompt="Select source: ")
    else
      src_path=$(find "$HOME" -type f \( -name "*.img" -o -name "*.img.xz" \) | fzf)
    fi
    [[ -z $src_path ]] && error "No source selected"
  fi

  if [[ -z $tgt_path ]]; then
    info "Interactive target selection"
    tgt_path=$(lsblk -dno NAME,SIZE,TYPE,RM |
      awk '$3=="disk" && ($4=="1" || $4=="0")' |
      fzf --prompt="Select target device: " | awk '{print "/dev/"$1}')
    [[ -z $tgt_path ]] && error "No target selected"
  fi

  # Validate boot size - ensure it has a unit suffix
  if [[ ! ${cfg[boot_size]} =~ [KMGT]$ && ! ${cfg[boot_size]} =~ [KMGT]iB$ ]]; then
    cfg[boot_size]="${cfg[boot_size]}M"
    info "Added unit to boot size: ${cfg[boot_size]}"
  fi

  # Execute pipeline
  info "Starting F2FS conversion"
  info "Source: $src_path"
  info "Target: $tgt_path"
  info "Boot size: ${cfg[boot_size]}"
  ((cfg[ssh])) && info "SSH will be enabled"

  prepare
  process_source
  setup_target
  partition_target
  mount_all
  copy_data
  update_config
  setup_boot
  finalize
}

# Run the script
main "$@"
