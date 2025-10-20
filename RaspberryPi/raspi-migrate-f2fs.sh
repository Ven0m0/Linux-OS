#!/usr/bin/env bash
# raspi-migrate-f2fs.sh - Migrate Raspberry Pi SD card from ext4 to F2FS
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob
export LC_ALL=C LANG=C

# Config
declare WORKDIR="" BOOT_MNT="" ROOT_MNT="" DEV="" BOOT_PART="" ROOT_PART="" ROOT_UUID=""

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }
error() {
  log "ERROR: $*" >&2
  cleanup
  exit 1
}

cleanup() {
  [[ -n ${BOOT_MNT:-} ]] && umount "$BOOT_MNT" &>/dev/null || :
  [[ -n ${ROOT_MNT:-} ]] && umount "$ROOT_MNT" &>/dev/null || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR"
}

check_deps() {
  local -a deps=(blkid mkfs.f2fs rsync parted lsblk)
  local cmd missing=0

  for cmd in "${deps[@]}"; do
    command -v "$cmd" &>/dev/null || {
      warn "Missing: $cmd"
      missing=1
    }
  done

  ((missing)) && error "Install: pacman -S f2fs-tools rsync parted util-linux"
}

detect_partitions() {
  local dev=$1

  if [[ $dev == *@(nvme|mmcblk|loop)* ]]; then
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  fi

  [[ -b $BOOT_PART && -b $ROOT_PART ]] || error "Partitions not found: $BOOT_PART $ROOT_PART"

  local fstype
  fstype=$(blkid -s TYPE -o value "$ROOT_PART")
  [[ $fstype == ext4 ]] || error "Root is $fstype, expected ext4"
}

backup_root() {
  info "Backing up root filesystem..."
  local backup="${WORKDIR}/root-backup"
  mkdir -p "$backup"

  mount "$ROOT_PART" "$ROOT_MNT"

  info "Copying data (this takes time)..."
  rsync -aHAX --info=progress2 "$ROOT_MNT/" "$backup/"

  umount "$ROOT_MNT"
  info "Backup complete: $(du -sh "$backup" | cut -f1)"
}

convert_to_f2fs() {
  info "Converting root partition to F2FS..."

  ROOT_UUID=$(blkid -s PARTUUID -o value "$ROOT_PART")

  wipefs -af "$ROOT_PART"
  mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum -l ROOT "$ROOT_PART"

  info "Restoring data to F2FS..."
  mount "$ROOT_PART" "$ROOT_MNT"
  rsync -aHAX --info=progress2 "${WORKDIR}/root-backup/" "$ROOT_MNT/"

  sync
}

update_boot_config() {
  info "Updating boot configuration..."
  mount "$BOOT_PART" "$BOOT_MNT"

  local cmdline="${BOOT_MNT}/cmdline.txt"
  [[ -f $cmdline ]] && {
    info "Patching cmdline.txt"
    sed -i -e "s|rootfstype=[^ ]*|rootfstype=f2fs|" \
      -e 's| init=/usr/lib/raspi-config/init_resize\.sh||' \
      "$cmdline"
  }

  local fstab="${ROOT_MNT}/etc/fstab"
  [[ -f $fstab ]] && {
    info "Updating fstab"
    sed -i "s|PARTUUID=${ROOT_UUID}.*|PARTUUID=${ROOT_UUID}  /  f2fs  noatime,discard  0 1|" "$fstab"
  }

  # DietPi-specific patches
  if [[ -d ${ROOT_MNT}/boot/dietpi ]]; then
    info "Applying DietPi patches"

    # Disable ext4 resize hooks
    local dietpi_stage="${ROOT_MNT}/boot/dietpi/.install_stage"
    [[ -f $dietpi_stage ]] && sed -i 's/resize2fs/# resize2fs (f2fs)/g' "$dietpi_stage" || :

    # Install F2FS tools on next boot
    mkdir -p "${ROOT_MNT}/var/lib/dietpi/postboot.d"
    cat >"${ROOT_MNT}/var/lib/dietpi/postboot.d/00-f2fs-tools.sh" <<-'EOFSCRIPT'
	#!/bin/bash
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq && apt-get install -y f2fs-tools
	rm -f "$0"
	EOFSCRIPT
    chmod +x "${ROOT_MNT}/var/lib/dietpi/postboot.d/00-f2fs-tools.sh"
  fi

  sync
  umount "$BOOT_MNT" "$ROOT_MNT"
}

main() {
  [[ $EUID -ne 0 ]] && error "Run as root: sudo $0 </dev/sdX>"

  DEV=${1:-}
  [[ -z $DEV || ! -b $DEV ]] && {
    info "Available devices:"
    lsblk -dno NAME,SIZE,TYPE,RM | awk '$3=="disk"&&$4=="1"'
    error "Usage: $0 </dev/sdX>"
  }

  check_deps
  trap cleanup EXIT INT TERM

  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}")
  BOOT_MNT="${WORKDIR}/boot"
  ROOT_MNT="${WORKDIR}/root"
  mkdir -p "$BOOT_MNT" "$ROOT_MNT"

  detect_partitions "$DEV"

  warn "WARNING: Converting $ROOT_PART (ext4 → f2fs)"
  info "Ensure you've booted DietPi at least once for initial setup"
  read -rp "Type YES to continue: " confirm
  [[ $confirm == YES ]] || error "Aborted"

  # Force unmount if mounted
  umount "${DEV}"* &>/dev/null || :

  backup_root
  convert_to_f2fs
  update_boot_config

  info "✓ Migration complete!"
  info "Remove SD card, insert into Pi, and boot"
  info "First boot will be slower while F2FS tools install"
}

main "$@"
