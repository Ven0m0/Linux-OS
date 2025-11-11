#!/usr/bin/env bash
# raspi-f2fs.sh - Flash Raspberry Pi images with F2FS root filesystem

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup environment
setup_environment
# Per common.sh: Explicitly override shell options after setup_environment().
# Disable options incompatible with this script; enable those required.
# execfail: Causes the shell to exit with a nonzero status if an exec fails, which can break error handling in this script.
# globstar: Enables recursive globbing (**), which may cause unintended file matches; this script expects standard globbing.
shopt -u execfail globstar  # Disable these for this script
shopt -s nullglob  # Keep nullglob enabled

# Config
declare -A cfg=([boot_size]="1024M" [ssh]=0 [dry_run]=0 [debug]=0 [keep_source]=0 [dietpi]=0)
declare src_path="" tgt_path="" IS_BLOCK=0 SRC_IMG="" WORKDIR="" LOOP_DEV="" TGT_DEV="" TGT_LOOP="" BOOT_PART="" ROOT_PART="" LOCK_FD=-1 LOCK_FILE="" STOPPED_UDISKS2=0

# Logging
log() { printf '[%s] %s\n' "$(date +%T)" "${1-}"; }
info() { log "INFO: $1"; }
warn() { log "WARN: $1" >&2; }
error() {
  log "ERROR: $1" >&2
  exit 1
}
debug() { ((cfg[debug])) && log "DEBUG: $1" || :; }

# Execute respecting dry-run
run() {
  ((cfg[dry_run])) && {
    info "[DRY] $*"
    return 0
  }
  debug "Run: $*"
  "$@"
}

# Derive partition paths using bash pattern matching
derive_partition_paths() {
  local dev=${1:-}
  [[ -z $dev ]] && {
    BOOT_PART=""
    ROOT_PART=""
    return
  }
  [[ $dev == *@(nvme|mmcblk|loop)* ]] && {
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  } || {
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  }
}

# Wait for partition devices
wait_for_partitions() {
  local boot=$1 root=$2 dev=${3:-$TGT_DEV} i
  ((cfg[dry_run])) && return 0

  for ((i = 0; i < 60; i++)); do
    [[ -b $boot && -b $root ]] && return 0
    ((i % 6 == 5 && ${#dev})) && {
      partprobe -s "$dev" &>/dev/null || :
      command -v udevadm &>/dev/null && udevadm settle &>/dev/null || :
    }
    sleep 0.5
  done

  error "Partitions unavailable: boot=$boot root=$root"
}

# Refresh partition table
refresh_partitions() {
  local dev=$1
  derive_partition_paths "$dev"
  ((cfg[dry_run])) && return 0

  sync

  if [[ $dev == /dev/loop* ]]; then
    debug "Refreshing loop partitions: $dev"
    losetup -d "$dev" &>/dev/null || :
    sleep 1
    TGT_LOOP=$(losetup --show -f -P "$tgt_path")
    TGT_DEV=$TGT_LOOP
    debug "Loop device reattached: $TGT_DEV"
  else
    debug "Refreshing partition table: $dev"

    # Try multiple methods with retries for block devices
    local retry
    for ((retry = 0; retry < 3; retry++)); do
      ((retry > 0)) && {
        warn "Retry $retry: forcing partition table refresh"
        sleep 2
      }

      command -v blockdev &>/dev/null && {
        blockdev --flushbufs "$dev" &>/dev/null || :
        blockdev --rereadpt "$dev" 2>/dev/null && break
      }

      partprobe -s "$dev" 2>/dev/null && break
    done

    command -v udevadm &>/dev/null && udevadm settle --timeout=10 &>/dev/null || sleep 2
  fi

  derive_partition_paths "$TGT_DEV"
  wait_for_partitions "$BOOT_PART" "$ROOT_PART"
}

# Device locking
acquire_device_lock() {
  local path=$1
  [[ -z $path ]] && return 0

  LOCK_FILE="/run/lock/raspi-f2fs.${path//[^[:alnum:]]/_}"
  mkdir -p "${LOCK_FILE%/*}"

  exec {LOCK_FD}>"$LOCK_FILE"
  flock -n "$LOCK_FD" || error "Lock failed: $path (in use)"
  debug "Lock acquired: $LOCK_FILE (fd=$LOCK_FD)"
}

release_device_lock() {
  ((LOCK_FD >= 0)) && {
    debug "Releasing lock"
    exec {LOCK_FD}>&-
    LOCK_FD=-1
  }
  [[ -n $LOCK_FILE ]] && rm -f "$LOCK_FILE" && LOCK_FILE=""
}

# Setup workspace
prepare() {
  info "Setting up workspace"
  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}")
  SRC_IMG="${WORKDIR}/source.img"
  mkdir -p "$WORKDIR"/{boot,root,target_{boot,root}}
  trap cleanup EXIT INT TERM
}

# Cleanup
cleanup() {
  debug "Cleaning up"
  local dir

  for dir in "${WORKDIR}/"{boot,root,target_{boot,root}}; do
    mountpoint -q "$dir" &>/dev/null && umount "$dir" &>/dev/null || :
  done

  [[ -n ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" &>/dev/null || :
  [[ -n ${TGT_LOOP:-} ]] && losetup -d "$TGT_LOOP" &>/dev/null || :

  # Restart udisks2 if we stopped it
  ((${STOPPED_UDISKS2:-0})) && {
    debug "Restarting udisks2"
    systemctl start udisks2.service 2>/dev/null || :
  }

  release_device_lock
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"
}

# Check dependencies
check_deps() {
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync tar xz blkid partprobe lsblk flock)
  local -a missing_cmds=()
  local cmd

  # Batch check all commands first, then report all missing at once
  for cmd in "${deps[@]}"; do
    command -v "$cmd" &>/dev/null || missing_cmds+=("$cmd")
  done

  if ((${#missing_cmds[@]} > 0)); then
    for cmd in "${missing_cmds[@]}"; do
      warn "Missing: $cmd"
    done
    error "Install missing dependencies (Arch: pacman -S f2fs-tools dosfstools parted rsync xz util-linux)"
  fi

  [[ -z $src_path || -z $tgt_path ]] && { command -v fzf &>/dev/null || error "fzf required for interactive mode (pacman -S fzf)"; }
}

# Force unmount device
force_umount_device() {
  local dev=$1 parts part

  # Kill any processes using the device
  command -v fuser &>/dev/null && {
    fuser -km "$dev" &>/dev/null 2>&1 || :
    sleep 1
  }

  # Find and unmount all partitions efficiently
  mapfile -t parts < <(lsblk -n -o NAME,MOUNTPOINT "$dev" 2>/dev/null | awk '$2!="" {print "/dev/"$1}')

  if ((${#parts[@]} > 0)); then
    warn "Unmounting partitions on $dev"
    # Unmount each partition individually for robustness
    for part in "${parts[@]}"; do
      umount -fl "$part" &>/dev/null 2>&1 || :
    done
    sleep 1
  fi

  # Force kernel to drop caches and release device
  sync
  echo 3 >/proc/sys/vm/drop_caches 2>/dev/null || :

  # Final fuser kill
  command -v fuser &>/dev/null && {
    fuser -km "$dev" &>/dev/null 2>&1 || :
    for part in "${parts[@]}"; do
      [[ -b $part ]] && fuser -km "$part" &>/dev/null 2>&1 || :
    done
  }

  sleep 2
}

# Process source
process_source() {
  info "Processing: $src_path"

  if [[ $src_path == *.xz ]]; then
    info "Extracting compressed image"
    xz -dc "$src_path" >"$SRC_IMG"
  elif ((cfg[keep_source])); then
    info "Copying source"
    cp --reflink=auto "$src_path" "$SRC_IMG"
  else
    SRC_IMG=$src_path
  fi

  [[ -f $SRC_IMG ]] || error "Source not found: $src_path"
}

# Setup target
setup_target() {
  info "Setting up: $tgt_path"
  acquire_device_lock "$tgt_path"

  if [[ -b $tgt_path ]]; then
    IS_BLOCK=1
    ((cfg[dry_run])) || {
      warn "WARNING: $tgt_path will be DESTROYED!"
      read -rp "Type YES to continue: " confirm
      [[ $confirm == YES ]] || error "Aborted"

      # Aggressive cleanup
      force_umount_device "$tgt_path"

      # Additional safety: try to release device
      command -v hdparm &>/dev/null && hdparm -z "$tgt_path" &>/dev/null 2>&1 || :

      sync
      sleep 2
    }
    TGT_DEV=$tgt_path
    ((cfg[dry_run])) || { command -v blockdev &>/dev/null && blockdev --flushbufs "$TGT_DEV" &>/dev/null || :; }
  else
    ((cfg[dry_run])) || {
      # Detach all existing loop devices for this path in one efficient pass
      mapfile -t existing < <(losetup -j "$tgt_path" 2>/dev/null | cut -d: -f1)
      # Batch detach if multiple loops exist
      ((${#existing[@]} > 0)) && {
        for loop in "${existing[@]}"; do
          [[ -n $loop ]] && losetup -d "$loop" &>/dev/null || :
        done
      }
    }

    local size_mb=$(($(du -m "$SRC_IMG" | cut -f1) + 200))

    info "Creating ${size_mb}MB image"
    run truncate -s "${size_mb}M" "$tgt_path"

    ((cfg[dry_run])) && TGT_DEV="loop-dev" || {
      TGT_LOOP=$(losetup --show -f -P "$tgt_path")
      TGT_DEV=$TGT_LOOP
    }
  fi

  derive_partition_paths "$TGT_DEV"
}

# Partition target
partition_target() {
  info "Partitioning"

  # For block devices, ensure complete device release before partitioning
  if [[ $TGT_DEV != /dev/loop* ]] && ((!cfg[dry_run])); then
    debug "Preparing block device for partitioning"

    # Final aggressive cleanup
    force_umount_device "$TGT_DEV"

    # Stop any automount services that might grab the device
    if systemctl is-active udisks2.service &>/dev/null; then
      warn "Stopping udisks2 temporarily"
      systemctl stop udisks2.service 2>/dev/null && STOPPED_UDISKS2=1 || :
    fi

    # Give kernel time to settle
    sync
    sleep 2
  fi

  # For loop devices, release and reattach for clean partitioning
  if [[ $TGT_DEV == /dev/loop* ]] && ((!cfg[dry_run])); then
    debug "Releasing loop device before partitioning"
    losetup -d "$TGT_DEV" &>/dev/null || :
    sync
    sleep 1
    TGT_LOOP=$(losetup --show -f "$tgt_path")
    TGT_DEV=$TGT_LOOP
    debug "Reattached as $TGT_DEV"
  fi

  # Zero beginning to clear any existing partition table
  ((cfg[dry_run])) || {
    dd if=/dev/zero of="$TGT_DEV" bs=1M count=10 conv=fsync 2>/dev/null || :
    sync
    sleep 2
  }

  run wipefs -af "$TGT_DEV"
  sync
  sleep 1

  run parted -s "$TGT_DEV" mklabel msdos
  sync
  sleep 1

  run parted -s "$TGT_DEV" mkpart primary fat32 0% "${cfg[boot_size]}"
  sync
  sleep 1

  run parted -s "$TGT_DEV" mkpart primary "${cfg[boot_size]}" 100%
  run parted -s "$TGT_DEV" set 1 boot on
  sync
  sleep 3

  # Refresh partition table (handles loop device reattach with -P flag)
  refresh_partitions "$TGT_DEV"

  info "Creating filesystems"
  run mkfs.vfat -F32 -I -n BOOT "$BOOT_PART"
  run mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l ROOT "$ROOT_PART"
}

# Mount filesystems
mount_all() {
  info "Mounting"
  ((cfg[dry_run])) && return 0

  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")

  local p1 p2
  [[ -b ${LOOP_DEV}p1 ]] && {
    p1="${LOOP_DEV}p1"
    p2="${LOOP_DEV}p2"
  } || {
    p1="${LOOP_DEV}1"
    p2="${LOOP_DEV}2"
  }

  wait_for_partitions "$p1" "$p2" "$LOOP_DEV"

  mount "$p1" "${WORKDIR}/boot"
  mount "$p2" "${WORKDIR}/root"
  mount "$BOOT_PART" "${WORKDIR}/target_boot"
  mount "$ROOT_PART" "${WORKDIR}/target_root"
}

# Copy data
copy_data() {
  info "Copying data"
  ((cfg[dry_run])) && return 0

  local -a dirs=(boot root)
  local dir size_mb free_mb

  for dir in "${dirs[@]}"; do
    size_mb=$(du -sm "${WORKDIR}/$dir" | cut -f1)
    free_mb=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)

    if ((free_mb >= size_mb * 2 && size_mb > 10)); then
      info "RAM buffer for $dir (${size_mb}MB)"
      (cd "${WORKDIR}/$dir" && tar -c .) | (cd "${WORKDIR}/target_$dir" && tar -x)
    else
      info "Direct copy for $dir"
      rsync -aHAX --info=progress2 "${WORKDIR}/$dir/" "${WORKDIR}/target_$dir/"
    fi
  done
}

# Update config
update_config() {
  info "Updating config for F2FS"
  ((cfg[dry_run])) && return 0

  local boot_partuuid root_partuuid
  boot_partuuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_partuuid=$(blkid -s PARTUUID -o value "$ROOT_PART")

  # Detect DietPi
  [[ -f ${WORKDIR}/target_root/boot/dietpi/.hw_model ]] && {
    info "DietPi image detected"
    cfg[dietpi]=1
  }

  # Update cmdline.txt
  [[ -f ${WORKDIR}/target_boot/cmdline.txt ]] && {
    info "Patching cmdline.txt"
    sed -i -e "s|root=[^ ]*|root=PARTUUID=$root_partuuid|" \
      -e "s|rootfstype=[^ ]*|rootfstype=f2fs|" \
      -e 's|rootwait|rootwait rootdelay=5|' \
      -e 's| init=/usr/lib/raspi-config/init_resize\.sh||' \
      -e 's| init=/usr/lib/raspberrypi-sys-mods/firstboot||' \
      "${WORKDIR}/target_boot/cmdline.txt"

    grep -q rootwait "${WORKDIR}/target_boot/cmdline.txt" || sed -i 's/$/ rootwait rootdelay=5/' "${WORKDIR}/target_boot/cmdline.txt"
  }

  # Update fstab
  cat >"${WORKDIR}/target_root/etc/fstab" <<-EOF
	proc                     /proc  proc    defaults          0  0
	PARTUUID=$boot_partuuid  /boot  vfat    defaults          0  2
	PARTUUID=$root_partuuid  /      f2fs    defaults,noatime  0  1
	EOF

  # Disable resize hooks
  ((cfg[dietpi])) && {
    local dietpi_stage="${WORKDIR}/target_root/boot/dietpi/.install_stage"
    [[ -f $dietpi_stage ]] && {
      info "Patching DietPi install stage"
      sed -i -e 's/resize2fs/# resize2fs (disabled for f2fs)/g' -e 's/parted.*resizepart/# parted resizepart (disabled)/g' "$dietpi_stage" || :
    }
  }

  local resize_service="${WORKDIR}/target_root/etc/systemd/system/multi-user.target.wants/rpi-set-sysconf.service"
  [[ -L $resize_service ]] && {
    info "Disabling rpi-set-sysconf resize service"
    rm -f "$resize_service"
  }
}

# Setup first boot configuration
setup_boot() {
  info "Setting up first boot"
  ((cfg[dry_run])) && return 0

  # Add kernel modules first
  local modules_file="${WORKDIR}/target_root/etc/modules"
  grep -q '^f2fs$' "$modules_file" 2>/dev/null || echo 'f2fs' >>"$modules_file"

  [[ -d ${WORKDIR}/target_root/etc/initramfs-tools ]] && {
    local initramfs_modules="${WORKDIR}/target_root/etc/initramfs-tools/modules"
    grep -q '^f2fs$' "$initramfs_modules" 2>/dev/null || echo 'f2fs' >>"$initramfs_modules"
  }

  # Create resize script that runs BEFORE mount (most reliable approach)
  mkdir -p "${WORKDIR}/target_root/usr/local/bin"
  cat >"${WORKDIR}/target_root/usr/local/bin/f2fs-resize-once.sh" <<-'EOFSCRIPT'
	#!/bin/bash
	# F2FS one-time resize script
	RESIZE_FLAG="/boot/.f2fs-resized"

	if [[ -f $RESIZE_FLAG ]]; then
	  exit 0
	fi

	# Install f2fs-tools if missing
	if ! command -v resize.f2fs &>/dev/null; then
	  export DEBIAN_FRONTEND=noninteractive
	  apt-get update -qq && apt-get install -y f2fs-tools || exit 0
	fi

	# Find root partition from fstab
	ROOT_PART=$(awk '$2=="/" && $1~/^PARTUUID=/ {gsub(/PARTUUID=/,"",$1); print $1}' /etc/fstab)
	[[ -z $ROOT_PART ]] && exit 0

	ROOT_DEV=$(blkid -t PARTUUID="$ROOT_PART" -o device)
	[[ -z $ROOT_DEV || ! -b $ROOT_DEV ]] && exit 0

	# Ensure root is mounted read-only
	if ! mount -o remount,ro / 2>/dev/null; then
	  # If remount fails, we're too late in boot - schedule for next boot via rc.local
	  exit 0
	fi

	# Resize filesystem
	if resize.f2fs "$ROOT_DEV" 2>/dev/null; then
	  mount -o remount,rw /
	  touch "$RESIZE_FLAG"
	fi
	EOFSCRIPT
  chmod +x "${WORKDIR}/target_root/usr/local/bin/f2fs-resize-once.sh"

  # Create systemd service that runs VERY early
  mkdir -p "${WORKDIR}/target_root/etc/systemd/system"
  cat >"${WORKDIR}/target_root/etc/systemd/system/f2fs-resize.service" <<-'EOFSERVICE'
	[Unit]
	Description=F2FS Root Filesystem Resize (First Boot)
	DefaultDependencies=no
	After=systemd-remount-fs.service
	Before=local-fs-pre.target
	ConditionPathExists=!/boot/.f2fs-resized

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/f2fs-resize-once.sh
	RemainAfterExit=yes
	StandardOutput=journal+console
	StandardError=journal+console

	[Install]
	WantedBy=sysinit.target
	EOFSERVICE

  mkdir -p "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants"
  ln -sf /etc/systemd/system/f2fs-resize.service "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants/f2fs-resize.service"

  # Create rc.local as absolute last resort fallback
  local rc_local="${WORKDIR}/target_root/etc/rc.local"
  cat >"$rc_local" <<-'EOFRC'
	#!/bin/bash
	# Last resort F2FS resize (should not normally execute)
	if [[ ! -f /boot/.f2fs-resized ]]; then
	  /usr/local/bin/f2fs-resize-once.sh
	fi
	exit 0
	EOFRC
  chmod +x "$rc_local"

  ((cfg[ssh])) && {
    info "Enabling SSH on first boot"
    touch "${WORKDIR}/target_boot/ssh" "${WORKDIR}/target_boot/SSH"
  }

  info "F2FS resize service installed"
}

# Complete
finalize() {
  info "Finalizing"
  ((cfg[dry_run])) || sync

  info "Complete!"
  ((IS_BLOCK)) && info "SD card ready: $tgt_path" || info "Image ready: $tgt_path"
  info "First boot will be ~30s slower while F2FS tools install and resize"
}

usage() {
  cat <<-EOF
	Usage: ${0##*/} [OPTIONS] [SOURCE] [TARGET]

	Flash Raspberry Pi images with F2FS root filesystem.

	OPTIONS:
	  -b SIZE   Boot size (default: ${cfg[boot_size]})
	  -i FILE   Source (.img / .img.xz)
	  -d DEV    Target device or file (optional for .img in-place)
	  -s        Enable SSH
	  -k        Keep source copy
	  -n        Dry run
	  -x        Debug
	  -h        Help

	EXAMPLES:
	  # Flash to SD card with SSH enabled
	  sudo ${0##*/} -s -i DietPi.img.xz -d /dev/sdX

	  # Create F2FS image file
	  ${0##*/} -i RaspberryPiOS.img -d output.img

	  # Modify image in-place (no target specified)
	  ${0##*/} -i DietPi.img

	  # Interactive mode
	  sudo ${0##*/}

	NOTES:
	  - Supports DietPi and Raspberry Pi OS
	  - First boot installs F2FS tools and resizes filesystem
	  - Omitting target for .img files enables in-place modification
	EOF
  exit 0
}

main() {
  while getopts "b:i:d:sknxh" opt; do
    case $opt in
    b) cfg[boot_size]=$OPTARG ;;
    i) src_path=$OPTARG ;;
    d) tgt_path=$OPTARG ;;
    s) cfg[ssh]=1 ;;
    k) cfg[keep_source]=1 ;;
    n) cfg[dry_run]=1 ;;
    x)
      cfg[debug]=1
      set -x
      ;;
    h) usage ;;
    *) usage ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -z $src_path && $# -ge 1 ]] && src_path=$1 && shift
  [[ -z $tgt_path && $# -ge 1 ]] && tgt_path=$1 && shift

  check_deps

  [[ -z $src_path ]] && {
    info "Select source"
    src_path=$(command -v fd &>/dev/null && fd -e img -e img.xz . "$HOME" | fzf --prompt="Source: " || find "$HOME" -type f \( -name "*.img" -o -name "*.img.xz" \) | fzf)
    [[ -z $src_path ]] && error "No source"
  }

  # Auto-detect in-place modification for .img files
  if [[ -z $tgt_path ]]; then
    if [[ $src_path == *.img && $src_path != *.xz ]]; then
      warn "No target specified - will modify source in-place"
      read -rp "Modify $src_path in-place? [y/N]: " confirm
      [[ $confirm =~ ^[Yy]$ ]] && {
        tgt_path="$src_path"
        cfg[keep_source]=0 # Force direct modification
        info "In-place modification enabled"
      }
    fi
  fi

  [[ -z $tgt_path ]] && {
    info "Select target"
    tgt_path=$(lsblk -dno NAME,SIZE,TYPE,RM | awk '$3=="disk"&&($4=="1"||$4=="0")' | fzf --prompt="Target: " | awk '{print "/dev/"$1}')
    [[ -z $tgt_path ]] && error "No target"
  }

  # Interactive boot size selection if not specified
  if [[ ${cfg[boot_size]} == "1024M" ]] && [[ -t 0 ]]; then
    info "Current boot partition size: ${cfg[boot_size]}"
    read -rp "Change boot size? [512M/1024M/2048M or press Enter to keep default]: " boot_input
    [[ -n $boot_input ]] && cfg[boot_size]=$boot_input
  fi

  [[ ${cfg[boot_size]} =~ [KMGT]i?B?$ ]] || cfg[boot_size]+="M"

  info "F2FS conversion starting"
  info "Source: $src_path | Target: $tgt_path | Boot: ${cfg[boot_size]}"
  ((cfg[ssh])) && info "SSH enabled"

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

main "$@"
