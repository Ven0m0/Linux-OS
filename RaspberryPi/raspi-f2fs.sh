#!/usr/bin/env bash
# raspi-f2fs.sh - Flash Raspberry Pi images with F2FS root filesystem
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob
export LC_ALL=C LANG=C

# Config
declare -A cfg=([boot_size]="512M" [ssh]=0 [dry_run]=0 [debug]=0 [keep_source]=0 [dietpi]=0)
declare src_path="" tgt_path="" IS_BLOCK=0 SRC_IMG="" WORKDIR="" LOOP_DEV="" TGT_DEV="" TGT_LOOP="" BOOT_PART="" ROOT_PART="" LOCK_FD=-1 LOCK_FILE=""

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
  local dev="${1:-}"
  [[ -z $dev ]] && {
    BOOT_PART=""
    ROOT_PART=""
    return
  }

  if [[ $dev == *@(nvme|mmcblk|loop)* ]]; then
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  fi
}

# Wait for partition devices
wait_for_partitions() {
  local boot=$1 root=$2 dev=${3:-$TGT_DEV} i
  ((cfg[dry_run])) && return 0

  for ((i = 0; i < 60; i++)); do
    [[ -b $boot && -b $root ]] && return 0

    if ((i % 6 == 5 && ${#dev})); then
      partprobe -s "$dev" &>/dev/null || :
      command -v udevadm &>/dev/null && udevadm settle &>/dev/null || :
    fi

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
    TGT_LOOP=$(losetup --show -f -P "$tgt_path")
    TGT_DEV=$TGT_LOOP
  else
    debug "Refreshing partition table: $dev"
    command -v blockdev &>/dev/null && {
      blockdev --flushbufs "$dev" &>/dev/null || :
      blockdev --rereadpt "$dev" &>/dev/null || :
    }
    partprobe -s "$dev" &>/dev/null || :
    command -v udevadm &>/dev/null && udevadm settle &>/dev/null || sleep 1
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
  mkdir -p "${WORKDIR}"/{boot,root,target_{boot,root}}
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

  release_device_lock
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"
}

# Check dependencies
check_deps() {
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync tar xz blkid partprobe lsblk flock)
  local cmd missing=0

  for cmd in "${deps[@]}"; do
    command -v "$cmd" &>/dev/null || {
      warn "Missing: $cmd"
      missing=1
    }
  done

  ((missing)) && error "Install missing dependencies (Arch: pacman -S f2fs-tools dosfstools parted rsync xz util-linux)"

  [[ -z $src_path || -z $tgt_path ]] && {
    command -v fzf &>/dev/null || error "fzf required for interactive mode (pacman -S fzf)"
  }
}

# Force unmount device
force_umount_device() {
  local dev=$1 parts part

  mapfile -t parts < <(lsblk -n -o NAME,MOUNTPOINT "$dev" | awk '$2!="" {print "/dev/"$1}')

  ((${#parts[@]})) && {
    warn "Unmounting partitions on $dev"
    for part in "${parts[@]}"; do
      umount -f "$part" &>/dev/null || :
    done
  }

  command -v fuser &>/dev/null && {
    fuser -k "$dev" &>/dev/null || :
    for part in "${parts[@]}"; do fuser -k "$part" &>/dev/null || :; done
  }

  sleep 1
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
      force_umount_device "$tgt_path"
    }
    TGT_DEV=$tgt_path
    ((cfg[dry_run])) || { command -v blockdev &>/dev/null && blockdev --flushbufs "$TGT_DEV" &>/dev/null || :; }
  else
    ((cfg[dry_run])) || {
      mapfile -t existing < <(losetup -j "$tgt_path" 2>/dev/null | cut -d: -f1)
      for loop in "${existing[@]}"; do [[ -n $loop ]] && losetup -d "$loop" &>/dev/null || :; done
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
  run wipefs -af "$TGT_DEV"
  sync
  sleep 1

  run parted -s "$TGT_DEV" mklabel msdos
  run parted -s "$TGT_DEV" mkpart primary fat32 0% "${cfg[boot_size]}"
  run parted -s "$TGT_DEV" mkpart primary "${cfg[boot_size]}" 100%
  sync

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

  local boot_uuid root_uuid
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")

  # Detect DietPi
  [[ -f ${WORKDIR}/target_root/boot/dietpi/.hw_model ]] && {
    info "DietPi image detected"
    cfg[dietpi]=1
  }

  [[ -f ${WORKDIR}/target_boot/cmdline.txt ]] && {
    info "Patching cmdline.txt"
    sed -i -e "s|root=[^ ]*|root=PARTUUID=$root_uuid|" \
      -e "s|rootfstype=[^ ]*|rootfstype=f2fs|" \
      -e 's| init=/usr/lib/raspi-config/init_resize\.sh||' \
      "${WORKDIR}/target_boot/cmdline.txt"
  }

  cat >"${WORKDIR}/target_root/etc/fstab" <<-EOF
	proc                 /proc  proc   defaults           0 0
	PARTUUID=$boot_uuid  /boot  vfat   defaults           0 2
	PARTUUID=$root_uuid  /      f2fs   noatime,discard    0 1
	EOF

  # Disable standard resize hooks
  ((cfg[dietpi])) && {
    local dietpi_stage="${WORKDIR}/target_root/boot/dietpi/.install_stage"
    [[ -f $dietpi_stage ]] && {
      info "Patching DietPi install stage for F2FS"
      sed -i 's/resize2fs/# resize2fs (disabled for f2fs)/g' "$dietpi_stage" || :
    }
  }
}

# Setup first boot configuration
setup_boot() {
  info "Setting up first boot"
  ((cfg[dry_run])) && return 0

  if ((cfg[dietpi])); then
    info "Configuring DietPi for F2FS"

    # Create postboot directory if missing
    mkdir -p "${WORKDIR}/target_root/var/lib/dietpi/postboot.d"

    # Create F2FS resize service (runs before DietPi automation)
    cat >"${WORKDIR}/target_root/etc/systemd/system/f2fs-resize.service" <<-'EOFSERVICE'
	[Unit]
	Description=F2FS Root Filesystem Resize
	DefaultDependencies=no
	After=local-fs-pre.target
	Before=local-fs.target shutdown.target
	Conflicts=shutdown.target
	ConditionPathExists=!/var/lib/dietpi/.f2fs-resized

	[Service]
	Type=oneshot
	RemainAfterExit=yes
	ExecStartPre=/bin/sh -c 'apt-get update -qq && apt-get install -y f2fs-tools'
	ExecStart=/bin/sh -c 'resize.f2fs $(findmnt -n -o SOURCE /)'
	ExecStartPost=/bin/touch /var/lib/dietpi/.f2fs-resized
	StandardOutput=journal
	StandardError=journal

	[Install]
	WantedBy=local-fs.target
	EOFSERVICE

    # Enable the service
    ln -sf /etc/systemd/system/f2fs-resize.service \
      "${WORKDIR}/target_root/etc/systemd/system/local-fs.target.wants/f2fs-resize.service"

    info "F2FS resize service installed (systemd)"
  else
    info "Configuring Raspberry Pi OS for F2FS"

    # For RPi OS: Use rc.local approach (more reliable than initramfs)
    local rc_local="${WORKDIR}/target_root/etc/rc.local"

    # Backup existing rc.local if present
    [[ -f $rc_local ]] && cp "$rc_local" "${rc_local}.bak"

    cat >"$rc_local" <<-'EOFRC'
	#!/bin/bash
	# F2FS resize on first boot
	if [[ ! -f /var/lib/.f2fs-resized ]]; then
	  export DEBIAN_FRONTEND=noninteractive
	  apt-get update -qq && apt-get install -y f2fs-tools
	  ROOT_DEV=$(findmnt -n -o SOURCE /)
	  if [[ -b $ROOT_DEV ]] && command -v resize.f2fs &>/dev/null; then
	    resize.f2fs "$ROOT_DEV"
	    touch /var/lib/.f2fs-resized
	  fi
	fi
	exit 0
	EOFRC
    chmod +x "$rc_local"

    info "F2FS resize script installed (rc.local)"
  fi

  ((cfg[ssh])) && {
    info "Enabling SSH on first boot"
    touch "${WORKDIR}/target_boot/ssh"
  }
}

# Complete
finalize() {
  info "Finalizing"
  ((cfg[dry_run])) || sync

  info "Complete!"
  ((IS_BLOCK)) && info "SD card ready: $tgt_path" || info "Image ready: $tgt_path"
}

usage() {
  cat <<-EOF
	Usage: ${0##*/} [OPTIONS] [SOURCE] [TARGET]

	OPTIONS:
	  -b SIZE   Boot size (default: ${cfg[boot_size]})
	  -i FILE   Source (.img / .img.xz)
	  -d DEV    Target device or file
	  -s        Enable SSH
	  -k        Keep source copy
	  -n        Dry run
	  -x        Debug
	  -h        Help

	NOTES:
	  - For DietPi images: F2FS tools installed automatically on first boot
	  - First boot will be slower due to filesystem resize
	  - Ensure adequate power supply during first boot
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
    *) usage ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ -z $src_path && $# -ge 1 ]] && src_path=$1 && shift
  [[ -z $tgt_path && $# -ge 1 ]] && tgt_path=$1 && shift

  check_deps

  [[ -z $src_path ]] && {
    info "Select source"
    src_path=$(command -v fd &>/dev/null \
      && fd -e img -e img.xz . "$HOME" | fzf --prompt="Source: " \
      || find "$HOME" -type f \( -name "*.img" -o -name "*.img.xz" \) | fzf)
    [[ -z $src_path ]] && error "No source"
  }

  [[ -z $tgt_path ]] && {
    info "Select target"
    tgt_path=$(lsblk -dno NAME,SIZE,TYPE,RM | awk '$3=="disk"&&($4=="1"||$4=="0")' \
      | fzf --prompt="Target: " | awk '{print "/dev/"$1}')
    [[ -z $tgt_path ]] && error "No target"
  }

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
