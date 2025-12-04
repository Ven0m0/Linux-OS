#!/usr/bin/env bash
# DESCRIPTION: Flash Raspberry Pi images (RaspiOS/DietPi) to SD card with F2FS root.
#              - Native Bash optimizations for speed.
#              - URL downloading & XZ streaming support.
#              - Auto-expands filesystem to fill SD card.
# USAGE: sudo ./raspi-f2fs.sh [-i image.xz | url | "dietpi"] [-d /dev/sdX]
# DEPENDENCIES: fzf, f2fs-tools, rsync, util-linux, parted, gawk, curl, xz
set -uo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}" PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin"

# --- Bash Native Tricks ---
# Faster date using printf builtin (Bash 4.2+)
fdate(){ local fmt="${1:-%T}"; printf "%($fmt)T" '-1'; }
# Faster cat using bash read (Memory intensive: Use only for text/config files!)
fcat(){ printf '%s\n' "$(<"${1}")"; }
# --- Configuration & State ---
declare -A cfg=(
  [boot_size]="512M" # Size of boot partition
  [ssh]=1            # Enable SSH by default
  [dry_run]=0
  [keep_source]=0
  [no_usb_check]=0   # bootiso safety override
  [no_size_check]=0  # bootiso safety override
)
# DietPi Shortcut
declare -r DIETPI_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"
# Colors
declare -r RED=$'\033[0;31m' GRN=$'\033[0;32m' YEL=$'\033[0;33m' BLD=$'\033[1m' DEF=$'\033[0m'
# Globals
declare -g SRC_PATH="" TGT_PATH="" SRC_IMG="" WORKDIR=""
declare -g LOOP_DEV="" TGT_DEV="" BOOT_PART="" ROOT_PART=""
declare -g LOCK_FD=-1 LOCK_FILE=""
declare -ga MOUNTED_DIRS=()
# --- Logging ---
log(){ printf '[%s] %s\n' "$(fdate)" "$*"; }
info(){ log "${GRN}INFO:${DEF} $*"; }
warn(){ log "${YEL}WARN:${DEF} $*" >&2; }
err(){ log "${RED}ERROR:${DEF} $*" >&2; }
die(){ err "$*"; cleanup; exit 1; }

# --- Bootiso-Derived Safety Modules ---
get_drive_trans(){ local dev="${1:?}"; lsblk -dno TRAN "$dev" 2> /dev/null || echo "unknown"; }
assert_usb_dev(){
  local dev="${1:?}"
  ((cfg[no_usb_check])) && return 0
  [[ $dev == /dev/loop* ]] && return 0
  local trans; trans=$(get_drive_trans "$dev")
  if [[ "$trans" != "usb" && "$trans" != "mmc" ]]; then
     die "Device $dev is not connected via USB/MMC (Detected: $trans). Use -U to bypass."
  fi
}

assert_size(){
  local img="${1:?}" dev="${2:?}"
  ((cfg[no_size_check])) && return 0
  [[ ! -b $dev ]] && return 0
  local img_bytes dev_bytes
  img_bytes=$(stat -c%s "$img")
  dev_bytes=$(blockdev --getsize64 "$dev")
  ((img_bytes > dev_bytes)) && \
    die "Image ($((img_bytes/1024/1024))MB) exceeds target ($((dev_bytes/1024/1024))MB)."
}

select_target_interactive(){
  command -v fzf >/dev/null || die "fzf is required for interactive selection."
  info "Scanning for removable drives..."
  local selection
  selection=$(
    lsblk -p -d -n -o NAME,MODEL,VENDOR,SIZE,TRAN,TYPE,HOTPLUG |
    awk -v skip="${cfg[no_usb_check]}" '
      tolower($0) ~ /disk/ && (skip == "1" || tolower($0) ~ /usb|mmc/) { print }
    ' | fzf --header="TARGET SELECTION (Safety: USB/MMC Only)" \
        --prompt="Select Drive > " --with-nth=1,2,3,4
  )
  [[ -z $selection ]] && die "No target selected."
  echo "$selection" | awk '{print $1}'
}

# --- Utils ---
check_deps(){
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync xz blkid partprobe lsblk flock awk curl)
  local cmd missing=()
  for cmd in "${deps[@]}"; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
  ((${#missing[@]} > 0)) && die "Missing dependencies: ${missing[*]}"
}

cleanup(){
  local ret="$?"; set +e
  for ((i=${#MOUNTED_DIRS[@]}-1; i>=0; i--)); do
    umount -lf "${MOUNTED_DIRS[i]}" &>/dev/null
  done
  [[ -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" &>/dev/null
  ((LOCK_FD >= 0)) && { exec {LOCK_FD}>&-; LOCK_FD=-1; }
  [[ -f ${LOCK_FILE:-} ]] && rm -f "$LOCK_FILE"
  [[ -n ${WORKDIR:-} && -d $WORKDIR ]] && rm -rf "$WORKDIR"
  return "$ret"
}

derive_partition_paths(){
  local dev="${1:?}"
  if [[ $dev =~ (nvme|mmcblk|loop) ]]; then
    BOOT_PART="${dev}p1"; ROOT_PART="${dev}p2"
  else
    BOOT_PART="${dev}1"; ROOT_PART="${dev}2"
  fi
}

wait_for_partitions(){
  local dev=${1:?}
  ((cfg[dry_run])) && return 0
  partprobe "$dev" &>/dev/null
  udevadm settle &>/dev/null
  sleep 1
  derive_partition_paths "$dev"
  local i
  for ((i=0; i<30; i++)); do
    [[ -b $BOOT_PART && -b $ROOT_PART ]] && return 0
    sleep 0.5
  done
  die "Partitions failed to appear on $dev"
}

# --- Main Logic ---

prepare_environment(){
  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" rf2fs.XXXXXX)
  SRC_IMG="$WORKDIR/source.img"
  trap cleanup EXIT INT TERM
  sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
}

process_source(){
  # Handle Keywords
  if [[ "$SRC_PATH" == "dietpi" ]]; then
    info "Keyword 'dietpi' detected. Using URL: $DIETPI_URL"
    SRC_PATH="$DIETPI_URL"
  fi
  # Handle URLs
  if [[ "$SRC_PATH" =~ ^https?:// ]]; then
    info "Downloading image from URL..."
    if [[ "$SRC_PATH" == *.xz ]]; then
      # Stream download -> decompress -> file
      curl -Lfs --progress-bar "$SRC_PATH" | xz -dc > "$SRC_IMG" || die "Download failed."
    else
      curl -Lfs --progress-bar "$SRC_PATH" -o "$SRC_IMG" || die "Download failed."
    fi
    return 0
  fi
  # Handle Local Files
  info "Processing local source: $SRC_PATH"
  [[ -f $SRC_PATH ]] || die "Source file not found."
  if [[ $SRC_PATH == *.xz ]]; then
    info "Decompressing xz archive..."
    xz -dc "$SRC_PATH" > "$SRC_IMG"
  elif ((cfg[keep_source])); then
    cp --reflink=auto "$SRC_PATH" "$SRC_IMG"
  else
    ln "$SRC_PATH" "$SRC_IMG" 2>/dev/null || cp "$SRC_PATH" "$SRC_IMG"
  fi
}

setup_target_device(){
  info "Preparing target: $TGT_PATH"
  LOCK_FILE="/run/lock/raspi-f2fs-${TGT_PATH//\//_}.lock"
  mkdir -p "${LOCK_FILE%/*}"
  exec {LOCK_FD}> "$LOCK_FILE" || die "Cannot create lock file"
  flock -n "$LOCK_FD" || die "Device $TGT_PATH is in use."
  assert_usb_dev "$TGT_PATH"
  assert_size "$SRC_IMG" "$TGT_PATH"
  ((cfg[dry_run])) && return 0
  warn "${RED}WARNING: ALL DATA ON $TGT_PATH WILL BE ERASED!${DEF}"
  wipefs -af "$TGT_PATH" &>/dev/null
  info "Partitioning..."
  parted -s "$TGT_PATH" mklabel msdos
  parted -s "$TGT_PATH" mkpart primary fat32 0% "${cfg[boot_size]}"
  parted -s "$TGT_PATH" mkpart primary "${cfg[boot_size]}" 100%
  parted -s "$TGT_PATH" set 1 boot on
  wait_for_partitions "$TGT_PATH"
  TGT_DEV="$TGT_PATH"
}

format_target(){
  info "Formatting filesystems..."
  ((cfg[dry_run])) && return 0
  mkfs.vfat -F32 -n BOOT "$BOOT_PART" >/dev/null
  mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum,compression "$ROOT_PART" >/dev/null
}

clone_data(){
  info "Cloning data (rsync)..."
  ((cfg[dry_run])) && return 0

  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")
  derive_partition_paths "$LOOP_DEV"
  
  mkdir -p "$WORKDIR"/{src,tgt}/{boot,root}
  mount -o ro "$BOOT_PART" "$WORKDIR/src/boot"
  MOUNTED_DIRS+=("$WORKDIR/src/boot")
  mount -o ro "$ROOT_PART" "$WORKDIR/src/root"
  MOUNTED_DIRS+=("$WORKDIR/src/root")

  derive_partition_paths "$TGT_DEV"
  mount "${BOOT_PART}" "$WORKDIR/tgt/boot"
  MOUNTED_DIRS+=("$WORKDIR/tgt/boot")
  mount "${ROOT_PART}" "$WORKDIR/tgt/root"
  MOUNTED_DIRS+=("$WORKDIR/tgt/root")

  info "Syncing /boot..."
  rsync -aHAX --info=progress2 "$WORKDIR/src/boot/" "$WORKDIR/tgt/boot/"

  info "Syncing / (Rootfs)..."
  rsync -aHAX --info=progress2 --exclude 'lost+found' "$WORKDIR/src/root/" "$WORKDIR/tgt/root/"
  sync
}

configure_pi_boot(){
  info "Configuring F2FS boot parameters..."
  ((cfg[dry_run])) && return 0

  local boot_uuid root_uuid cmdline fstab
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")
  cmdline="$WORKDIR/tgt/boot/cmdline.txt"
  fstab="$WORKDIR/tgt/root/etc/fstab"

  # awk optimization for atomic cmdline editing
  awk -v uuid="$root_uuid" '{
    line=""
    for(i=1;i<=NF;i++) {
      if($i ~ /^root=/) $i="root=PARTUUID=" uuid
      else if($i ~ /^rootfstype=/) $i="rootfstype=f2fs"
      else if($i ~ /^init=.*init_resize\.sh/) continue
      line = (line ? line " " : "") $i
    }
    if(line !~ /rootwait/) line = line " rootwait"
    if(line !~ /fsck\.repair=yes/) line = line " fsck.repair=yes"
    print line
  }' "$cmdline" > "${cmdline}.tmp" && mv "${cmdline}.tmp" "$cmdline"

  # Use fcat for verifying content (demonstration of trick)
  # log "Verified cmdline: $(fcat "$cmdline")"

  cat > "$fstab" <<- EOF
	proc            /proc           proc    defaults          0       0
	PARTUUID=$boot_uuid  /boot           vfat    defaults          0       2
	PARTUUID=$root_uuid  /               f2fs    defaults,noatime  0       1
EOF

  ((cfg[ssh])) && touch "$WORKDIR/tgt/boot/ssh"
  info "Configuration complete."
}

usage(){
  cat <<- EOF
	Usage: $(basename "$0") [OPTIONS]
	
	Flash Raspberry Pi image to SD card using F2FS root filesystem.
	
	OPTIONS:
	  -i FILE   Source image (.img, .img.xz, URL, or 'dietpi')
	  -d DEV    Target device (e.g., /dev/sdX)
	  -b SIZE   Boot partition size (default: 256M)
	  -s        Enable SSH
	  -k        Keep source file (don't delete if extracted)
	  -U        Disable USB/MMC safety check (Dangerous)
	  -F        Disable Size safety check
	  -n        Dry-run
	  -h        Help
EOF
  exit 0
}

# --- Entry Point ---

while getopts "b:i:d:sknxhUF" opt; do
  case $opt in
    b) cfg[boot_size]=$OPTARG ;;
    i) SRC_PATH=$OPTARG ;;
    d) TGT_PATH=$OPTARG ;;
    s) cfg[ssh]=1 ;;
    k) cfg[keep_source]=1 ;;
    n) cfg[dry_run]=1 ;;
    U) cfg[no_usb_check]=1 ;;
    F) cfg[no_size_check]=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ $EUID -ne 0 ]] && die "This script requires root privileges (sudo)."
check_deps

if [[ -z $SRC_PATH ]]; then
  SRC_PATH=$(find . -maxdepth 2 -name "*.img*" -o -name "*.xz" | fzf --prompt="Select Source Image (or enter URL/dietpi) > ")
  [[ -z $SRC_PATH ]] && die "No source image selected."
fi

if [[ -z $TGT_PATH ]]; then
  TGT_PATH=$(select_target_interactive)
fi

prepare_environment
process_source
setup_target_device
format_target
clone_data
configure_pi_boot

info "${GRN}SUCCESS:${DEF} Flashed to $TGT_PATH with F2FS."
info "You can now safely remove the device."
