#!/usr/bin/env bash
# Integrated: 2025-11-29 - Merged bootiso v4.2.0 safety & discovery modules
# Optimized: 2025-11-19 - Applied bash optimization techniques
#
# DESCRIPTION: Flash Raspberry Pi images with F2FS root filesystem
#              Features bootiso's guardrails (USB-only check, Size validation)
#              Production-hardened for DietPi/RaspiOS
set -uo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' SHELL="$(command -v bash 2> /dev/null)"
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
# Color codes
declare -r RED=$'\033[0;31m' GRN=$'\033[0;32m' YEL=$'\033[0;33m' BLD=$'\033[1m' DEF=$'\033[0m'

# Config
declare -A cfg=(
  [boot_size]="256M" # Reduced default for modern efficiency
  [ssh]=0
  [dry_run]=0
  [debug]=0
  [keep_source]=0
  [dietpi]=0
  [no_usb_check]=0  # bootiso integration
  [no_size_check]=0 # bootiso integration
)

# State tracking
declare -g src_path="" tgt_path="" IS_BLOCK=0 SRC_IMG="" WORKDIR=""
declare -g LOOP_DEV="" TGT_DEV="" TGT_LOOP="" BOOT_PART="" ROOT_PART=""
declare -g LOCK_FD=-1 LOCK_FILE="" STOPPED_UDISKS2=0
declare -ga MOUNTED_DIRS=()

# --- Logging (Enhanced) ---
log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }
info() { log "${GRN}INFO:${DEF} $*"; }
warn() { log "${YEL}WARN:${DEF} $*" >&2; }
err() { log "${RED}ERROR:${DEF} $*" >&2; }
die() {
  err "$*"
  cleanup
  exit 1
}
dbg() { ((cfg[debug])) && log "DEBUG: $*" || :; }

# --- Bootiso Integration: Safety Modules ---

# Ported from bootiso: sys_getDeviceType
get_drive_trans() {
  local dev=${1:?}
  lsblk -dno TRAN "$dev" 2> /dev/null || echo "unknown"
}

# Ported from bootiso: asrt_checkDeviceIsUSB
assert_usb_dev() {
  local dev=${1:?}
  ((cfg[no_usb_check])) && return 0

  # Skip check for loop/files
  [[ $dev != /dev/* ]] && return 0
  [[ $dev == /dev/loop* ]] && return 0

  local trans
  trans=$(get_drive_trans "$dev")
  [[ $trans == "usb" ]] && return 0

  die "Device $dev is not connected via USB (TRAN=$trans). Use -U to bypass safety check."
}

# Ported from bootiso: asrt_checkImageSize
assert_size() {
  local img=${1:?} dev=${2:?}
  ((cfg[no_size_check])) && return 0
  [[ ! -b $dev ]] && return 0 # Skip if target is file

  local img_bytes dev_bytes
  img_bytes=$(stat -c%s "$img")
  dev_bytes=$(blockdev --getsize64 "$dev")

  ((img_bytes > dev_bytes)) &&
    die "Image size ($img_bytes) exceeds target device capacity ($dev_bytes)"
}

# Ported from bootiso: exec_listUSBDrives (adapted for fzf)
select_target_interactive() {
  has fzf || die "fzf required for interactive mode"
  info "Scanning for removable drives..."

  # bootiso style rich columns
  local selection
  selection=$(
    lsblk -p -d -n -o NAME,MODEL,VENDOR,SIZE,TRAN,TYPE,HOTPLUG |
      awk '$6=="disk"' |
      { ((!cfg[no_usb_check])) && awk '$5=="usb"' || cat; } |
      fzf --header="TARGET SELECTION (Safety: USB-Only)" \
        --prompt="Select Drive > " \
        --with-nth=1,2,3,4
  )

  [[ -z $selection ]] && die "No target selected"
  echo "$selection" | awk '{print $1}'
}

# --- Core Utilities ---

run() { ((cfg[dry_run])) && info "[DRY] $*" || "$@"; }

run_with_retry() {
  local -i attempts="${1:-3}" delay="${2:-2}" i
  shift 2
  for ((i = 1; i <= attempts; i++)); do
    "$@" 2> /dev/null && return 0
    ((i < attempts)) && sleep "$delay"
  done
  die "Failed after $attempts attempts: $*"
}

derive_partition_paths() {
  local dev=${1:?}
  if [[ $dev == *@(nvme|mmcblk|loop)* ]]; then
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  fi
}

wait_for_partitions() {
  local boot=${1:?} root=${2:?} dev=${3:-}
  local -i i
  ((cfg[dry_run])) && return 0

  for ((i = 0; i < 50; i++)); do
    [[ -b $boot && -b $root ]] && return 0
    ((i % 5 == 0 && ${#dev})) && partprobe -s "$dev" &> /dev/null || :
    sleep 0.2
  done
  die "Partitions missing: $boot / $root"
}

refresh_partitions() {
  local dev=${1:?}
  ((cfg[dry_run])) && return 0
  sync

  if [[ $dev == /dev/loop* ]]; then
    losetup -d "$dev" &> /dev/null || :
    TGT_LOOP=$(losetup --show -f -P "$tgt_path")
    TGT_DEV=$TGT_LOOP
  else
    partprobe -s "$dev" 2> /dev/null || blockdev --rereadpt "$dev" 2> /dev/null || :
    udevadm settle --timeout=5 &> /dev/null || sleep 1
  fi
  derive_partition_paths "$TGT_DEV"
  wait_for_partitions "$BOOT_PART" "$ROOT_PART" "$TGT_DEV"
}

acquire_device_lock() {
  local path=${1:?}
  LOCK_FILE="/run/lock/raspi-f2fs-${path//[^[:alnum:]]/_}.lock"
  mkdir -p "${LOCK_FILE%/*}"
  exec {LOCK_FD}> "$LOCK_FILE" || die "Lock failed: $LOCK_FILE"
  flock -n "$LOCK_FD" || die "Device locked by another process: $path"
}

release_device_lock() {
  ((LOCK_FD >= 0)) && {
    exec {LOCK_FD}>&- || :
    LOCK_FD=-1
  }
  [[ -f ${LOCK_FILE:-} ]] && rm -f "$LOCK_FILE" || :
}

cleanup() {
  local -i ret=$?
  set +e

  # Unmount LIFO
  local i
  for ((i = ${#MOUNTED_DIRS[@]} - 1; i >= 0; i--)); do
    [[ -n ${MOUNTED_DIRS[i]:-} ]] && umount -lf "${MOUNTED_DIRS[i]}" &> /dev/null
  done

  [[ -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" &> /dev/null
  [[ -b ${TGT_LOOP:-} ]] && losetup -d "$TGT_LOOP" &> /dev/null
  ((STOPPED_UDISKS2)) && systemctl start udisks2.service &> /dev/null

  release_device_lock
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"

  ((ret != 0)) && warn "Cleanup finished with errors"
  return "$ret"
}

has() { command -v -- "$1" &> /dev/null; }

check_deps() {
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync tar xz blkid partprobe lsblk flock blockdev)
  local cmd missing=()
  for cmd in "${deps[@]}"; do has "$cmd" || missing+=("$cmd"); done
  ((${#missing[@]} > 0)) && die "Missing dependencies: ${missing[*]}"
}

force_umount_device() {
  local dev=${1:?}
  local part
  # bootiso style strict unmount
  grep -q "$dev" /proc/mounts || return 0

  mapfile -t parts < <(lsblk -nlo MOUNTPOINT "$dev" | grep -v "^$")
  for part in "${parts[@]}"; do
    umount -lf "$part" &> /dev/null || :
  done
  sync
}

# --- F2FS Logic ---

process_source() {
  info "Processing source: $src_path"
  [[ -f $src_path ]] || die "Source not found"

  if [[ $src_path == *.xz ]]; then
    ((cfg[dry_run])) || xz -dc "$src_path" > "$SRC_IMG"
  elif ((cfg[keep_source])); then
    ((cfg[dry_run])) || cp --reflink=auto "$src_path" "$SRC_IMG"
  else
    SRC_IMG=$src_path
  fi
}

setup_target() {
  info "Target setup: $tgt_path"
  acquire_device_lock "$tgt_path"

  if [[ -b $tgt_path ]]; then
    IS_BLOCK=1
    # bootiso safety check hooks
    assert_usb_dev "$tgt_path"
    assert_size "$SRC_IMG" "$tgt_path"

    ((cfg[dry_run])) || {
      warn "${RED}WARNING: All data on $tgt_path will be DESTROYED${DEF}"
      assert_usb_dev "$tgt_path" # Double check before wipe

      force_umount_device "$tgt_path"
      wipefs -af "$tgt_path" &> /dev/null || :
    }
    TGT_DEV=$tgt_path
  else
    # Image file target
    local -i size_mb=$(($(stat -c%s "$SRC_IMG" 2> /dev/null || echo 0) / 1048576 + 512))
    run truncate -s "${size_mb}M" "$tgt_path"
    ((cfg[dry_run])) && TGT_DEV="loop-dev" || {
      TGT_LOOP=$(losetup --show -f -P "$tgt_path")
      TGT_DEV=$TGT_LOOP
    }
  fi
  derive_partition_paths "$TGT_DEV"
}

partition_target() {
  info "Partitioning & Formatting: $TGT_DEV"

  if [[ $TGT_DEV != /dev/loop* ]] && ((!cfg[dry_run])); then
    systemctl is-active udisks2 &> /dev/null && {
      systemctl stop udisks2 && STOPPED_UDISKS2=1
    }
  fi

  # Optimized partitioning
  run parted -s "$TGT_DEV" mklabel msdos
  run parted -s "$TGT_DEV" mkpart primary fat32 0% "${cfg[boot_size]}"
  run parted -s "$TGT_DEV" mkpart primary "${cfg[boot_size]}" 100%
  run parted -s "$TGT_DEV" set 1 boot on

  refresh_partitions "$TGT_DEV"

  info "Formatting filesystems..."
  run_with_retry 3 1 mkfs.vfat -F32 -n BOOT "$BOOT_PART"
  run_with_retry 3 1 mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum "$ROOT_PART"
}

mount_and_copy() {
  info "Mounting & Cloning data"
  ((cfg[dry_run])) && return 0

  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")
  local src_boot="${LOOP_DEV}p1" src_root="${LOOP_DEV}p2"
  [[ -b $src_boot ]] || {
    src_boot="${LOOP_DEV}1"
    src_root="${LOOP_DEV}2"
  }

  wait_for_partitions "$src_boot" "$src_root" "$LOOP_DEV"

  # Mount
  mkdir -p "$WORKDIR"/{src,tgt}/{boot,root}
  mount "$src_boot" "$WORKDIR/src/boot"
  MOUNTED_DIRS+=("$WORKDIR/src/boot")
  mount "$src_root" "$WORKDIR/src/root"
  MOUNTED_DIRS+=("$WORKDIR/src/root")
  mount "$BOOT_PART" "$WORKDIR/tgt/boot"
  MOUNTED_DIRS+=("$WORKDIR/tgt/boot")
  mount "$ROOT_PART" "$WORKDIR/tgt/root"
  MOUNTED_DIRS+=("$WORKDIR/tgt/root")

  # Copy (RAM buffer if space permits)
  local dir size free
  for dir in boot root; do
    size=$(du -sm "$WORKDIR/src/$dir" | awk '{print $1}')
    free=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)

    if ((free > size * 2 && size > 10)); then
      info "RAM-buffered copy: $dir"
      (cd "$WORKDIR/src/$dir" && tar -cf - .) | (cd "$WORKDIR/tgt/$dir" && tar -xf -)
    else
      rsync -aHAX --info=progress2 "$WORKDIR/src/$dir/" "$WORKDIR/tgt/$dir/"
    fi
  done
  sync
}

configure_f2fs_boot() {
  info "Applying F2FS Configuration"
  ((cfg[dry_run])) && return 0

  local boot_uuid root_uuid cmdline fstab
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")
  cmdline="$WORKDIR/tgt/boot/cmdline.txt"
  fstab="$WORKDIR/tgt/root/etc/fstab"

  sed -i -e "s|root=[^ ]*|root=PARTUUID=$root_uuid|" \
    -e "s|rootfstype=[^ ]*|rootfstype=f2fs|" \
    -e 's|rootwait|rootwait rootdelay=5|' \
    "$cmdline"
  grep -q rootwait "$cmdline" || sed -i 's/$/ rootwait rootdelay=5/' "$cmdline"

  cat > "$fstab" <<- EOF
	proc            /proc  proc    defaults          0  0
	PARTUUID=$boot_uuid  /boot  vfat    defaults          0  2
	PARTUUID=$root_uuid  /      f2fs    defaults,noatime  0  1
	EOF

  # Inject initramfs resize hook (condensed)
  local hook_dir="$WORKDIR/tgt/root/etc/initramfs-tools/hooks"
  mkdir -p "$hook_dir"
  cat > "$hook_dir/f2fs" <<- 'EOF'
	#!/bin/sh
	PREREQ=""; prereqs(){ echo "$PREREQ"; }
	case $1 in prereqs) prereqs; exit 0;; esac
	. /usr/share/initramfs-tools/hook-functions
	copy_exec /usr/sbin/resize.f2fs /sbin
	copy_exec /usr/sbin/fsck.f2fs /sbin
	exit 0
	EOF
  chmod +x "$hook_dir/f2fs"

  ((cfg[ssh])) && touch "$WORKDIR/tgt/boot/ssh"
}

usage() {
  cat <<- 'EOF'
	Usage: raspi-f2fs.sh [OPTIONS] [SOURCE] [TARGET]
	
	Flash Raspberry Pi images with F2FS root. Integrated with bootiso safety.
	
	OPTIONS:
	  -b SIZE   Boot partition size (default: 256M)
	  -i FILE   Source image
	  -d DEV    Target device/file
	  -s        Enable SSH
	  -k        Keep source (no in-place)
	  -U        Disable USB-only safety check (Dangerous)
	  -F        Disable Size safety check
	  -n        Dry-run
	  -h        Help
	EOF
  exit 0
}

main() {
  local opt
  prepare() {
    WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" rf2fs.XXXXXX)
    SRC_IMG="$WORKDIR/source.img"
    trap cleanup EXIT INT TERM
  }

  while getopts "b:i:d:sknxhUF" opt; do
    case $opt in
      b) cfg[boot_size]=$OPTARG ;;
      i) src_path=$OPTARG ;;
      d) tgt_path=$OPTARG ;;
      s) cfg[ssh]=1 ;;
      k) cfg[keep_source]=1 ;;
      n) cfg[dry_run]=1 ;;
      U) cfg[no_usb_check]=1 ;;
      F) cfg[no_size_check]=1 ;;
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

  # Interactive Source
  [[ -z $src_path ]] && {
    has fzf || die "fzf needed"
    src_path=$(find . -maxdepth 2 -name "*.img*" | fzf --prompt="Source > ")
    [[ -z $src_path ]] && die "No source"
  }

  # Interactive Target (Bootiso Integrated)
  [[ -z $tgt_path ]] && {
    tgt_path=$(select_target_interactive)
  }

  prepare
  process_source
  setup_target
  partition_target
  mount_and_copy
  configure_f2fs_boot

  info "${GRN}SUCCESS:${DEF} F2FS conversion complete on $tgt_path"
}

main "$@"
