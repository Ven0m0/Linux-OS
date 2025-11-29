#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques
#
# DESCRIPTION: Flash Raspberry Pi images with F2FS root filesystem
#              Production-hardened for DietPi/RaspiOS on SD cards
#              Zero-tolerance error handling for critical operations

set -Eeuo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

# Color codes
declare -r RED=$'\033[0;31m' GRN=$'\033[0;32m' BLD=$'\033[1m' DEF=$'\033[0m'
# Config
declare -A cfg=(
  [boot_size]="1024M"
  [ssh]=0
  [dry_run]=0
  [debug]=0
  [keep_source]=0
  [dietpi]=0
)

# State tracking (critical for cleanup)
declare -g src_path="" tgt_path="" IS_BLOCK=0 SRC_IMG="" WORKDIR=""
declare -g LOOP_DEV="" TGT_DEV="" TGT_LOOP="" BOOT_PART="" ROOT_PART=""
declare -g LOCK_FD=-1 LOCK_FILE="" STOPPED_UDISKS2=0
declare -ga MOUNTED_DIRS=()

# Logging
log(){ printf '[%s] %s\n' "$(date +%T)" "$*"; }
info(){ log "INFO: $*"; }
warn(){ log "WARN: $*" >&2; }
err(){ log "ERROR: $*" >&2; }
die(){
  err "$*"
  cleanup
  exit 1
}
dbg(){ ((cfg[debug])) && log "DEBUG: $*" || :; }

# Execute w/ dry-run support
run(){
  ((cfg[dry_run])) && {
    info "[DRY] $*"
    return 0
  }
  dbg "Run: $*"
  "$@"
}

# Safe command execution with retries
run_with_retry(){
  local -i attempts="${1:-3}" delay="${2:-2}" i
  shift 2

  for ((i = 1; i <= attempts; i++)); do
    if "$@" 2>/dev/null; then
      return 0
    fi
    ((i < attempts)) && {
      warn "Retry $i/$attempts: $*"
      sleep "$delay"
    }
  done

  die "Failed after $attempts attempts: $*"
}

# Derive partition paths (nvme/mmcblk/loop use 'p' separator)
derive_partition_paths(){
  local dev=${1:?}

  if [[ $dev == *@(nvme|mmcblk|loop)* ]]; then
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  fi

  dbg "Partitions: boot=$BOOT_PART root=$ROOT_PART"
}

# Wait for partition devices with exponential backoff
wait_for_partitions(){
  local boot=${1:?} root=${2:?} dev=${3:-}
  local -i i sleep_ms=100

  ((cfg[dry_run])) && return 0

  for ((i = 0; i < 60; i++)); do
    [[ -b $boot && -b $root ]] && {
      dbg "Partitions ready: boot=$boot root=$root"
      return 0
    }

    # Aggressive refresh every 3s
    ((i % 6 == 5 && ${#dev})) && {
      partprobe -s "$dev" &>/dev/null>/dev/null || :
      has udevadm && udevadm settle --timeout=5 &>/dev/null>/dev/null || :
    }

    # Exponential backoff capped at 1s
    ((sleep_ms < 1000)) && sleep_ms=$((sleep_ms * 11 / 10))
    sleep "0.$(printf '%03d' "$sleep_ms")"
  done

  die "Partitions unavailable after 30s: boot=$boot root=$root"
}

# Refresh partition table with multiple fallback strategies
refresh_partitions(){
  local dev=${1:?}

  derive_partition_paths "$dev"
  ((cfg[dry_run])) && return 0

  # Optimized: Single sync is sufficient
  sync

  if [[ $dev == /dev/loop* ]]; then
    dbg "Loop device partition refresh: $dev"

    # Detach and reattach with -P for partition scan
    local old_dev=$dev
    losetup -d "$dev" &>/dev/null>/dev/null || :
    sleep 1

    TGT_LOOP=$(losetup --show -f -P "$tgt_path")
    TGT_DEV=$TGT_LOOP

    [[ $TGT_DEV != "$old_dev" ]] && dbg "Loop device changed: $old_dev → $TGT_DEV"
  else
    dbg "Block device partition refresh: $dev"

    # Multi-strategy refresh for stubborn hardware
    local -i attempt
    for ((attempt = 0; attempt < 5; attempt++)); do
      ((attempt > 0)) && {
        warn "Partition refresh retry $attempt/5"
        sleep 2
      }

      # Strategy 1: blockdev
      if has blockdev; then
        blockdev --flushbufs "$dev" &>/dev/null>/dev/null || :
        blockdev --rereadpt "$dev" 2>/dev/null && break
      fi

      # Strategy 2: partprobe
      partprobe -s "$dev" 2>/dev/null && break

      # Strategy 3: partx (if available)
      if has partx; then
        partx -u "$dev" 2>/dev/null && break
      fi
    done

    has udevadm && udevadm settle --timeout=10 &>/dev/null>/dev/null || sleep 3
  fi

  derive_partition_paths "$TGT_DEV"
  wait_for_partitions "$BOOT_PART" "$ROOT_PART" "$TGT_DEV"
}

# Device locking with flock
acquire_device_lock(){
  local path=${1:?}

  LOCK_FILE="/run/lock/raspi-f2fs-${path//[^[:alnum:]]/_}.lock"
  mkdir -p "${LOCK_FILE%/*}"

  exec {LOCK_FD}> "$LOCK_FILE" || die "Cannot create lock file: $LOCK_FILE"
  flock -n "$LOCK_FD" || die "Device locked (already in use): $path"

  dbg "Lock acquired: $LOCK_FILE (fd=$LOCK_FD)"
}

release_device_lock(){
  ((LOCK_FD >= 0)) && {
    dbg "Releasing lock fd=$LOCK_FD"
    exec {LOCK_FD}>&- || :
    LOCK_FD=-1
  }
  [[ -f ${LOCK_FILE:-} ]] && rm -f "$LOCK_FILE" || :
  LOCK_FILE=""
}

# Track mounted directories for guaranteed cleanup
track_mount(){
  local dir=${1:?}
  MOUNTED_DIRS+=("$dir")
  dbg "Tracked mount: $dir"
}

# Safe unmount with force fallback
safe_umount(){
  local dir=${1:?}
  local -i attempt

  mountpoint -q "$dir" || return 0

  for ((attempt = 1; attempt <= 3; attempt++)); do
    if umount "$dir" &>/dev/null>/dev/null; then
      dbg "Unmounted: $dir"
      return 0
    fi

    ((attempt == 2)) && {
      warn "Force unmount: $dir"
      has fuser && fuser -km "$dir" &>/dev/null>/dev/null 2>&1 || :
      sleep 1
    }

    ((attempt == 3)) && {
      warn "Lazy unmount fallback: $dir"
      umount -l "$dir" &>/dev/null>/dev/null || :
      return 0
    }

    sleep 1
  done

  warn "Failed to unmount: $dir"
}

# Comprehensive cleanup with ordering guarantees
cleanup(){
  local -i exit_code=$?

  set +e # Continue cleanup on errors
  dbg "Cleanup starting (exit_code=$exit_code)"

  # Unmount in reverse order (LIFO)
  local -i i
  for ((i = ${#MOUNTED_DIRS[@]} - 1; i >= 0; i--)); do
    [[ -n ${MOUNTED_DIRS[i]:-} ]] && safe_umount "${MOUNTED_DIRS[i]}"
  done

  # Detach loop devices
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV} ]] && {
    dbg "Detaching source loop: $LOOP_DEV"
    losetup -d "$LOOP_DEV" &>/dev/null>/dev/null || :
  }

  [[ -n ${TGT_LOOP:-} && -b ${TGT_LOOP} ]] && {
    dbg "Detaching target loop: $TGT_LOOP"
    losetup -d "$TGT_LOOP" &>/dev/null>/dev/null || :
  }

  # Restart services
  ((STOPPED_UDISKS2)) && {
    dbg "Restarting udisks2"
    systemctl start udisks2.service 2>/dev/null || :
  }

  # Release lock
  release_device_lock

  # Remove workspace
  [[ -d ${WORKDIR:-} ]] && {
    dbg "Removing workspace: $WORKDIR"
    rm -rf "$WORKDIR" || :
  }

  ((exit_code != 0)) && err "Cleanup complete (with errors)"

  return "$exit_code"
}

# Check command availability
has(){ command -v -- "$1" &>/dev/null>/dev/null; }

# Dependency validation
check_deps(){
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync tar xz blkid partprobe lsblk flock blockdev sync)
  local -a missing=() pkg_hints=()
  local cmd

  for cmd in "${deps[@]}"; do
    has "$cmd" || missing+=("$cmd")
  done

  ((${#missing[@]} == 0)) && return 0

  err "Missing required tools: ${missing[*]}"

  # Distro-specific hints
  if has pacman; then
    pkg_hints+=("pacman -S f2fs-tools dosfstools parted rsync xz util-linux")
  elif has apt-get; then
    pkg_hints+=("apt-get install f2fs-tools dosfstools parted rsync xz-utils util-linux")
  fi

  ((${#pkg_hints[@]} > 0)) && err "Install: ${pkg_hints[*]}"
  die "Cannot proceed without dependencies"
}

# Force device release (aggressive)
force_umount_device(){
  local dev=${1:?}
  local -a parts=()

  dbg "Forcing release: $dev"

  # Kill processes with device handles
  has fuser && {
    fuser -km "$dev" &>/dev/null>/dev/null 2>&1 || :
    sleep 1
  }

  # Unmount all partitions
  mapfile -t parts < <(lsblk -nlo NAME,MOUNTPOINT "$dev" 2>/dev/null | awk '$2 {print "/dev/"$1}')

  for part in "${parts[@]}"; do
    [[ -n $part ]] && umount -fl "$part" &>/dev/null>/dev/null 2>&1 || :
  done

  # Kernel cache drop (sync once before cache drop)
  sync
  printf '3\n' > /proc/sys/vm/drop_caches 2>/dev/null || :

  # Final process kill
  has fuser && {
    fuser -km "$dev" &>/dev/null>/dev/null 2>&1 || :
    for part in "${parts[@]}"; do
      [[ -b $part ]] && fuser -km "$part" &>/dev/null>/dev/null 2>&1 || :
    done
  }

  sleep 2
}

# Process source image
process_source(){
  info "Processing source: $src_path"

  [[ -f $src_path || -b $src_path ]] || die "Source not found: $src_path"

  if [[ $src_path == *.xz ]]; then
    info "Decompressing .xz archive"
    ((cfg[dry_run])) || xz -dc "$src_path" > "$SRC_IMG"
  elif ((cfg[keep_source])); then
    info "Copying source (CoW if supported)"
    ((cfg[dry_run])) || cp --reflink=auto "$src_path" "$SRC_IMG"
  else
    SRC_IMG=$src_path
  fi

  [[ -f $SRC_IMG ]] || die "Source processing failed: $src_path"
}

# Setup target device/image
setup_target(){
  info "Target setup: $tgt_path"

  acquire_device_lock "$tgt_path"

  if [[ -b $tgt_path ]]; then
    IS_BLOCK=1

    ((cfg[dry_run])) || {
      warn "${RED}DESTRUCTIVE: $tgt_path will be ERASED${DEF}"
      warn "Type exactly: DESTROY"

      local confirm
      read -rp "> " confirm
      [[ $confirm == DESTROY ]] || die "Aborted by user"

      force_umount_device "$tgt_path"

      has hdparm && hdparm -z "$tgt_path" &>/dev/null>/dev/null 2>&1 || :
      sync
      sync
      sleep 2
    }

    TGT_DEV=$tgt_path
    ((cfg[dry_run])) || blockdev --flushbufs "$TGT_DEV" &>/dev/null>/dev/null || :
  else
    # Image file target
    ((cfg[dry_run])) || {
      # Detach any existing loops for this path
      local -a existing=()
      mapfile -t existing < <(losetup -j "$tgt_path" 2>/dev/null | awk -F: '{print $1}')

      for loop in "${existing[@]}"; do
        [[ -n $loop ]] && losetup -d "$loop" &>/dev/null>/dev/null || :
      done
    }

    local -i size_mb=$(($(stat -c%s "$SRC_IMG" 2>/dev/null || echo 0) / 1048576 + 256))

    info "Creating ${size_mb}MB image file"
    run truncate -s "${size_mb}M" "$tgt_path"

    ((cfg[dry_run])) && TGT_DEV="loop-dev" || {
      TGT_LOOP=$(losetup --show -f -P "$tgt_path") || die "losetup failed: $tgt_path"
      TGT_DEV=$TGT_LOOP
    }
  fi

  derive_partition_paths "$TGT_DEV"
}

# Partition target with comprehensive safety
partition_target(){
  info "Partitioning: $TGT_DEV"

  # Pre-partition device prep
  if [[ $TGT_DEV != /dev/loop* ]] && ((!cfg[dry_run])); then
    force_umount_device "$TGT_DEV"

    # Stop automounters temporarily
    if systemctl is-active udisks2.service &>/dev/null>/dev/null; then
      warn "Stopping udisks2 for partitioning"
      systemctl stop udisks2.service 2>/dev/null && STOPPED_UDISKS2=1 || :
      sleep 2
    fi

    sync
    sleep 2
  fi

  # Loop device refresh before partitioning
  if [[ $TGT_DEV == /dev/loop* ]] && ((!cfg[dry_run])); then
    losetup -d "$TGT_DEV" &>/dev/null>/dev/null || :
    sync
    sleep 1
    TGT_LOOP=$(losetup --show -f "$tgt_path") || die "Loop reattach failed"
    TGT_DEV=$TGT_LOOP
  fi

  # Zero MBR + partition table
  ((cfg[dry_run])) || {
    dd if=/dev/zero of="$TGT_DEV" bs=1M count=10 conv=fsync status=none 2>/dev/null || :
    # conv=fsync already syncs; one additional sync is sufficient
    sync
    sleep 2
  }

  run wipefs -af "$TGT_DEV"
  sync
  sleep 1

  # Partition table creation
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

  # Critical: refresh partition table
  refresh_partitions "$TGT_DEV"

  # Filesystem creation
  info "Creating filesystems"
  run_with_retry 3 2 mkfs.vfat -F32 -I -n BOOT "$BOOT_PART"
  run_with_retry 3 2 mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l ROOT "$ROOT_PART"

  sync
  sleep 2
}

# Mount all filesystems with tracking
mount_all(){
  info "Mounting filesystems"
  ((cfg[dry_run])) && return 0

  # Attach source image
  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG") || die "Source losetup failed: $SRC_IMG"

  local src_boot src_root
  if [[ -b ${LOOP_DEV}p1 ]]; then
    src_boot="${LOOP_DEV}p1"
    src_root="${LOOP_DEV}p2"
  else
    src_boot="${LOOP_DEV}1"
    src_root="${LOOP_DEV}2"
  fi

  wait_for_partitions "$src_boot" "$src_root" "$LOOP_DEV"

  # Mount with tracking (reverse order for unmount)
  mount "$src_boot" "${WORKDIR}/boot" || die "Mount failed: source boot"
  track_mount "${WORKDIR}/boot"

  mount "$src_root" "${WORKDIR}/root" || die "Mount failed: source root"
  track_mount "${WORKDIR}/root"

  mount "$BOOT_PART" "${WORKDIR}/target_boot" || die "Mount failed: target boot"
  track_mount "${WORKDIR}/target_boot"

  mount "$ROOT_PART" "${WORKDIR}/target_root" || die "Mount failed: target root"
  track_mount "${WORKDIR}/target_root"

  dbg "All filesystems mounted successfully"
}

# Copy data with RAM buffering optimization
copy_data(){
  info "Copying filesystem data"
  ((cfg[dry_run])) && return 0

  local -a dirs=(boot root)
  local dir size_mb free_mb

  for dir in "${dirs[@]}"; do
    size_mb=$(du -sm "${WORKDIR}/$dir" | awk '{print $1}')
    free_mb=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)

    # RAM buffer if we have 2x headroom and >10MB
    if ((free_mb >= size_mb * 2 && size_mb > 10)); then
      info "RAM-buffered copy: $dir (${size_mb}MB)"
      (cd "${WORKDIR}/$dir" && tar -c .) | (cd "${WORKDIR}/target_$dir" && tar -x) || die "Copy failed: $dir"
    else
      info "Direct rsync: $dir"
      rsync -aHAX --info=progress2 "${WORKDIR}/$dir/" "${WORKDIR}/target_$dir/" || die "Rsync failed: $dir"
    fi
  done

  sync
}

# Update boot/root configuration for F2FS
update_config(){
  info "Configuring F2FS boot parameters"
  ((cfg[dry_run])) && return 0

  local boot_uuid root_uuid
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART") || die "Cannot read boot PARTUUID"
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART") || die "Cannot read root PARTUUID"

  # DietPi detection
  [[ -f ${WORKDIR}/target_root/boot/dietpi/.hw_model ]] && {
    info "DietPi image detected"
    cfg[dietpi]=1
  }

  # cmdline.txt patch
  local cmdline="${WORKDIR}/target_boot/cmdline.txt"
  [[ -f $cmdline ]] && {
    info "Patching cmdline.txt"
    sed -i \
      -e "s|root=[^ ]]*|root=PARTUUID=$root_uuid|" \
      -e "s|rootfstype=[^ ]]*|rootfstype=f2fs|" \
      -e 's|rootwait|rootwait rootdelay=5|' \
      -e 's| init=/usr/lib/raspi-config/init_resize\.sh||' \
      -e 's| init=/usr/lib/raspberrypi-sys-mods/firstboot||' \
      "$cmdline"

    grep -q rootwait "$cmdline" || sed -i 's/$/ rootwait rootdelay=5/' "$cmdline"
  }

  # fstab generation
  cat > "${WORKDIR}/target_root/etc/fstab" <<- EOF || die "fstab creation failed"
	proc                    /proc  proc    defaults          0  0
	PARTUUID=$boot_uuid     /boot  vfat    defaults          0  2
	PARTUUID=$root_uuid     /      f2fs    defaults,noatime  0  1
  EOF
  
  # Disable resize hooks
  if (( cfg[dietpi] )); then
    local stage="${WORKDIR}/target_root/boot/dietpi/.install_stage"
    [[ -f $stage ]] && {
      info "Disabling DietPi resize hooks"
      sed -i \
        -e 's/resize2fs/# resize2fs (f2fs)/g' \
        -e 's/parted.*resizepart/# parted resizepart (f2fs)/g' \
        "$stage" || warn "DietPi stage patch failed (non-critical)"
    }
  fi
  local resize_svc="${WORKDIR}/target_root/etc/systemd/system/multi-user.target.wants/rpi-set-sysconf.service"
  [[ -L $resize_svc ]] && {
    info "Disabling rpi-set-sysconf"
    rm -f "$resize_svc"
  }
}

# Setup first-boot F2FS resize with initramfs hook
setup_boot(){
  info "Installing F2FS resize mechanism (initramfs + fallbacks)"
  (( cfg[dry_run] )) && return 0

  local has_initramfs=0
  [[ -d ${WORKDIR}/target_root/etc/initramfs-tools ]] && has_initramfs=1

  # Add kernel module loading
  local modules="${WORKDIR}/target_root/etc/modules"
  grep -q '^f2fs$' "$modules" 2>/dev/null || echo 'f2fs' >>"$modules"

  # Initramfs approach (most correct - runs before root mount)
  if (( has_initramfs )); then
    info "Setting up initramfs hook for pre-mount resize"

    # Add f2fs module to initramfs
    local initrd_mods="${WORKDIR}/target_root/etc/initramfs-tools/modules"
    grep -q '^f2fs$' "$initrd_mods" 2>/dev/null || echo 'f2fs' >>"$initrd_mods"

    # Create initramfs hook to copy f2fs-tools binaries
    mkdir -p "${WORKDIR}/target_root/etc/initramfs-tools/hooks"
    cat >"${WORKDIR}/target_root/etc/initramfs-tools/hooks/f2fs" <<-'INITRAMFS_HOOK' || die "Initramfs hook creation failed"
	#!/bin/sh
	# Hook to include f2fs-tools in initramfs

	PREREQ=""
	prereqs(){ echo "$PREREQ"; }
	case $1 in prereqs) prereqs; exit 0;; esac

	. /usr/share/initramfs-tools/hook-functions

	# Copy f2fs utilities if they exist
	if [[ -x /usr/sbin/resize.f2fs ]]; then
	  copy_exec /usr/sbin/resize.f2fs /sbin
	fi
	if [[ -x /usr/sbin/fsck.f2fs ]]; then
	  copy_exec /usr/sbin/fsck.f2fs /sbin
	fi
	if [[ -x /usr/sbin/mkfs.f2fs ]]; then
	  copy_exec /usr/sbin/mkfs.f2fs /sbin
	fi

	# Copy required libraries
	for lib in /lib/*/libf2fs.so* /usr/lib/*/libf2fs.so*; do
	  [[ -e "$lib" ]] && copy_exec "$lib"
	done

	exit 0
	INITRAMFS_HOOK

    chmod +x "${WORKDIR}/target_root/etc/initramfs-tools/hooks/f2fs"

    # Create initramfs script for actual resize (runs in initramfs environment)
    mkdir -p "${WORKDIR}/target_root/etc/initramfs-tools/scripts/local-premount"
    cat >"${WORKDIR}/target_root/etc/initramfs-tools/scripts/local-premount/f2fs_resize" <<-'INITRAMFS_SCRIPT' || die "Initramfs script creation failed"
	#!/bin/sh
	# F2FS resize script - runs in initramfs before root mount

	PREREQ=""
	prereqs(){ echo "$PREREQ"; }
	case $1 in prereqs) prereqs; exit 0;; esac

	. /scripts/functions

	# Check if already resized
	RESIZE_FLAG_DIR="/tmp/boot_check"
	mkdir -p "$RESIZE_FLAG_DIR"

	# Extract root device from kernel command line
	ROOT_PARTUUID=""
	for x in $(cat /proc/cmdline); do
	  case $x in
	    root=PARTUUID=*)
	      ROOT_PARTUUID=${x#root=PARTUUID=}
	      ;;
	    root=/dev/*)
	      ROOT_DEV=${x#root=}
	      ;;
	  esac
	done

	# Exit early if no root found
	[[ -z "$ROOT_PARTUUID" ]] && [[ -z "$ROOT_DEV" ]] && exit 0

	# Resolve PARTUUID to device
	if [[ -n "$ROOT_PARTUUID" ]]; then
	  wait_for_udev 10
	  ROOT_DEV=$(blkid -t PARTUUID="$ROOT_PARTUUID" -o device 2>/dev/null)
	fi

	# Exit if device not found
	[[ -z "$ROOT_DEV" ]] || [[ ! -b "$ROOT_DEV" ]] && exit 0

	# Find boot partition (typically same disk, partition 1)
	BOOT_DEV="${ROOT_DEV%[0-9]*}1"
	[[ "$BOOT_DEV" = "$ROOT_DEV" ]] && BOOT_DEV="${ROOT_DEV%p[0-9]*}p1"

	# Mount boot partition temporarily to check flag
	if [[ -b "$BOOT_DEV" ]]; then
	  mount -t vfat -o ro "$BOOT_DEV" "$RESIZE_FLAG_DIR" 2>/dev/null || exit 0

	  if [[ -f "$RESIZE_FLAG_DIR/.f2fs-resized" ]]; then
	    umount "$RESIZE_FLAG_DIR" 2>/dev/null
	    exit 0
	  fi

	  # Remount rw for flag creation
	  mount -o remount,rw "$RESIZE_FLAG_DIR" 2>/dev/null || {
	    umount "$RESIZE_FLAG_DIR" 2>/dev/null
	    exit 0
	  }
	fi

	# Perform resize if resize.f2fs is available
	if command -v resize.f2fs >/dev/null 2>&1; then
	  log_begin_msg "Resizing F2FS root filesystem"

	  if resize.f2fs "$ROOT_DEV" >/dev/null 2>&1; then
	    log_success_msg "F2FS resize completed"
	    # Create flag to prevent future resize attempts
	    [[ -d "$RESIZE_FLAG_DIR" ]] && touch "$RESIZE_FLAG_DIR/.f2fs-resized" 2>/dev/null
	  else
	    log_failure_msg "F2FS resize failed (non-fatal)"
	  fi

	  log_end_msg
	fi

	# Cleanup
	[[ -d "$RESIZE_FLAG_DIR" ]] && umount "$RESIZE_FLAG_DIR" 2>/dev/null

	exit 0
	INITRAMFS_SCRIPT

    chmod +x "${WORKDIR}/target_root/etc/initramfs-tools/scripts/local-premount/f2fs_resize"

    # Create first-boot service to install f2fs-tools and regenerate initramfs
    mkdir -p "${WORKDIR}/target_root/etc/systemd/system"
    cat >"${WORKDIR}/target_root/etc/systemd/system/f2fs-initramfs-setup.service" <<-'INITRAMFS_SETUP' || die "Initramfs setup service creation failed"
	[Unit]
	Description=F2FS Tools Installation and Initramfs Regeneration (First Boot)
	DefaultDependencies=no
	After=systemd-remount-fs.service network-online.target
	Before=local-fs-pre.target
	ConditionPathExists=!/boot/.f2fs-initramfs-ready

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/f2fs-initramfs-setup.sh
	RemainAfterExit=yes
	StandardOutput=journal+console
	StandardError=journal+console

	[Install]
	WantedBy=sysinit.target
	INITRAMFS_SETUP

    mkdir -p "${WORKDIR}/target_root/usr/local/bin"
    cat >"${WORKDIR}/target_root/usr/local/bin/f2fs-initramfs-setup.sh" <<-'INITRAMFS_SETUP_SCRIPT' || die "Initramfs setup script creation failed"
	#!/usr/bin/env bash
	set -euo pipefail

	SETUP_FLAG="/boot/.f2fs-initramfs-ready"
	[[ -f $SETUP_FLAG ]] && exit 0

	echo "==> Installing f2fs-tools and regenerating initramfs..."

	# Install f2fs-tools if missing
	if ! command -v resize.f2fs &>/dev/null; then
	  export DEBIAN_FRONTEND=noninteractive
	  apt-get update -qq || exit 1
	  apt-get install -y f2fs-tools || exit 1
	fi

	# Regenerate initramfs with f2fs support
	if command -v update-initramfs &>/dev/null; then
	  echo "==> Regenerating initramfs with F2FS support..."
	  update-initramfs -u || {
	    echo "WARNING: initramfs regeneration failed"
	    exit 1
	  }
	fi

	# Mark as complete and schedule reboot
	touch "$SETUP_FLAG"
	sync

	echo "==> F2FS initramfs setup complete. Rebooting in 5 seconds..."
	sleep 5
	reboot
	INITRAMFS_SETUP_SCRIPT

    chmod +x "${WORKDIR}/target_root/usr/local/bin/f2fs-initramfs-setup.sh"

    mkdir -p "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants"
    ln -sf ../f2fs-initramfs-setup.service "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants/f2fs-initramfs-setup.service"
  fi

  # Fallback 1: Systemd service (for systems without initramfs or if initramfs fails)
  info "Adding systemd fallback resize service"
  mkdir -p "${WORKDIR}/target_root/usr/local/bin"
  cat >"${WORKDIR}/target_root/usr/local/bin/f2fs-resize-once.sh" <<-'RESIZE_SCRIPT' || die "Resize script creation failed"
	#!/usr/bin/env bash
	set -euo pipefail

	RESIZE_FLAG="/boot/.f2fs-resized"
	[[ -f $RESIZE_FLAG ]] && exit 0

	# Install f2fs-tools if missing
	if ! command -v resize.f2fs &>/dev/null; then
	  export DEBIAN_FRONTEND=noninteractive
	  apt-get update -qq && apt-get install -y f2fs-tools &>/dev/null || exit 0
	fi

	# Find root partition
	ROOT_UUID=$(awk '$2=="/" && $1~/^PARTUUID=/ {gsub(/PARTUUID=/,"",$1); print $1}' /etc/fstab)
	[[ -z $ROOT_UUID ]] && exit 0

	ROOT_DEV=$(blkid -t PARTUUID="$ROOT_UUID" -o device 2>/dev/null)
	[[ -z $ROOT_DEV || ! -b $ROOT_DEV ]] && exit 0

	echo "==> Resizing F2FS root filesystem (fallback method)..."

	# Remount root RO for safe resize
	if mount -o remount,ro / 2>/dev/null; then
	  # Perform resize
	  if resize.f2fs "$ROOT_DEV" &>/dev/null; then
	    mount -o remount,rw /
	    touch "$RESIZE_FLAG"
	    sync
	    echo "==> F2FS resize completed successfully"
	  else
	    mount -o remount,rw /
	    echo "WARNING: F2FS resize failed"
	  fi
	fi
	RESIZE_SCRIPT

  chmod +x "${WORKDIR}/target_root/usr/local/bin/f2fs-resize-once.sh"

  mkdir -p "${WORKDIR}/target_root/etc/systemd/system"
  cat >"${WORKDIR}/target_root/etc/systemd/system/f2fs-resize-fallback.service" <<-'RESIZE_SERVICE' || die "Systemd service creation failed"
	[Unit]
	Description=F2FS Root Filesystem Resize (Fallback Method)
	DefaultDependencies=no
	After=systemd-remount-fs.service f2fs-initramfs-setup.service
	Before=local-fs-pre.target
	ConditionPathExists=!/boot/.f2fs-resized
	ConditionPathExists=/boot/.f2fs-initramfs-ready

	[Service]
	Type=oneshot
	ExecStart=/usr/local/bin/f2fs-resize-once.sh
	RemainAfterExit=yes
	StandardOutput=journal+console
	StandardError=journal+console

	[Install]
	WantedBy=sysinit.target
	RESIZE_SERVICE

  mkdir -p "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants"
  ln -sf ../f2fs-resize-fallback.service "${WORKDIR}/target_root/etc/systemd/system/sysinit.target.wants/f2fs-resize-fallback.service"

  # Fallback 2: rc.local (ultimate fallback for non-systemd or failures)
  info "Adding rc.local ultimate fallback"
  cat >"${WORKDIR}/target_root/etc/rc.local" <<-'RC_LOCAL' || die "rc.local creation failed"
	#!/usr/bin/env bash
	[[ ! -f /boot/.f2fs-resized ]] && /usr/local/bin/f2fs-resize-once.sh
	exit 0
	RC_LOCAL

  chmod +x "${WORKDIR}/target_root/etc/rc.local"

  # SSH enablement
  (( cfg[ssh] )) && {
    info "Enabling SSH on first boot"
    touch "${WORKDIR}/target_boot/ssh" "${WORKDIR}/target_boot/SSH"
  }

  sync
}

# Finalize and report
finalize(){
  info "Finalizing"
  (( cfg[dry_run] )) || sync

  info "${GRN}✓${DEF} F2FS conversion complete"
  (( IS_BLOCK )) && info "SD card ready: $tgt_path" || info "Image ready: $tgt_path"

  # Check if initramfs setup was added
  if [[ -f ${WORKDIR}/target_root/etc/initramfs-tools/scripts/local-premount/f2fs_resize ]]; then
    info ""
    info "${BLD}First Boot Process:${DEF}"
    info "  1. Boot 1: Install f2fs-tools, regenerate initramfs (~30-90s), auto-reboot"
    info "  2. Boot 2: Initramfs resizes F2FS before root mount (seamless)"
    info "  3. System ready with full F2FS capacity"
    info ""
    info "Note: Two boots required for initramfs-based resize"
  else
    info "First boot: F2FS tools install + resize (~30-60s delay)"
  fi
}

usage(){
  cat <<-'EOF'
	Usage: raspi-f2fs.sh [OPTIONS] [SOURCE] [TARGET]
	
	Flash Raspberry Pi images with F2FS root filesystem.
	Production-hardened for DietPi and Raspberry Pi OS.
	
	OPTIONS:
	  -b SIZE   Boot partition size (default: 1024M)
	  -i FILE   Source image (.img or .img.xz)
	  -d DEV    Target device or file
	  -s        Enable SSH on first boot
	  -k        Keep source copy (no in-place mod)
	  -n        Dry-run mode
	  -x        Debug mode
	  -h        Show this help
	
	EXAMPLES:
	  # Flash to SD card with SSH
	  sudo raspi-f2fs.sh -s -i dietpi.img.xz -d /dev/sdX
	
	  # Create F2FS image file
	  raspi-f2fs.sh -i raspios.img -d output.img
	
	  # In-place conversion (no target)
	  raspi-f2fs.sh -i dietpi.img
	
	  # Interactive mode with fzf
	  sudo raspi-f2fs.sh
	
	SAFETY:
	  - Comprehensive error handling
	  - Guaranteed cleanup on failure
	  - Device locking prevents conflicts
	  - Multi-strategy partition refresh
	  - Automatic retry on transient failures
	
	NOTES:
	  - Requires root for block devices
	  - Uses initramfs hook for optimal resize (2 boots required)
	  - First boot: installs f2fs-tools, regenerates initramfs, reboots
	  - Second boot: initramfs resizes F2FS before root mount
	  - Fallback resize methods if initramfs unavailable
	  - Supports both DietPi and Raspberry Pi OS
	EOF
  exit 0
}

# Prepare workspace
prepare(){
  info "Preparing workspace"

  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" raspi-f2fs.XXXXXX) || die "mktemp failed"
  SRC_IMG="${WORKDIR}/source.img"

  mkdir -p "$WORKDIR"/{boot,root,target_boot,target_root} || die "mkdir failed"

  trap cleanup EXIT INT TERM QUIT HUP
}

# Main entry point
main(){
  local opt

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

  # Positional fallback
  [[ -z $src_path && $# -ge 1 ]] && src_path=$1 && shift
  [[ -z $tgt_path && $# -ge 1 ]] && tgt_path=$1 && shift

  check_deps

  # Interactive source selection
  [[ -z $src_path ]] && {
    has fzf || die "fzf required for interactive mode"
    info "Select source image"

    src_path=$(
      has fd && fd -e img -e xz . "$HOME" 2>/dev/null | fzf --prompt="Source: " \
        || find "$HOME" -type f \( -name "*.img" -o -name "*.img.xz" \) 2>/dev/null | fzf --prompt="Source: "
    )
    [[ -z $src_path ]] && die "No source selected"
  }

  # Auto-detect in-place modification
  if [[ -z $tgt_path && $src_path == *.img && $src_path != *.xz ]]; then
    warn "No target specified - in-place modification mode"

    local reply
    read -rp "Modify $src_path in-place? [y/N]: " reply
    [[ $reply =~ ^[Yy]$ ]] && {
      tgt_path=$src_path
      cfg[keep_source]=0
      info "In-place mode enabled"
    }
  fi

  # Interactive target selection
  [[ -z $tgt_path ]] && {
    has fzf || die "fzf required for interactive mode"
    info "Select target device"

    tgt_path=$(
      lsblk -dno NAME,SIZE,TYPE,RM 2>/dev/null \
        | awk '$3=="disk" && ($4=="1" || $4=="0")' \
        | fzf --prompt="Target: " \
        | awk '{print "/dev/"$1}'
    )
    [[ -z $tgt_path ]] && die "No target selected"
  }

  # Boot size validation
  [[ ${cfg[boot_size]} =~ ^[0-9]+[KMGT]i?B?$ ]] || cfg[boot_size]+="M"

  # Summary
  info "${BLD}F2FS Conversion Starting${DEF}"
  info "Source:    $src_path"
  info "Target:    $tgt_path"
  info "Boot size: ${cfg[boot_size]}"
  ((cfg[ssh])) && info "SSH:       enabled"
  ((cfg[dry_run])) && warn "DRY-RUN MODE"

  # Execute pipeline
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
