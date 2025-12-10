#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
s=${BASH_SOURCE[0]}; [[ $s != /* ]] && s=$PWD/$s; cd -P -- "${s%/*}"
fdate(){ local fmt="${1:-%T}"; printf "%($fmt)T" '-1'; }
fcat(){ printf '%s\n' "$(<"${1}")"; }
declare -A cfg=([boot_size]="512M" [ssh]=1 [dry_run]=0 [keep_source]=0 [no_usb_check]=0 [no_size_check]=0 [shrink]=0)
declare -r DIETPI_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m' LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m' DEF=$'\e[0m' BLD=$'\e[1m'
declare -r RED GRN YLW BLU DEF BLD
declare -g SRC_PATH="" TGT_PATH="" SRC_IMG="" WORKDIR="" LOOP_DEV="" TGT_DEV="" BOOT_PART="" ROOT_PART="" LOCK_FD=-1 LOCK_FILE="" -ga MOUNTED_DIRS=()
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "[$(fdate)] ${BLU}${BLD}[*]${DEF} $*"; }
msg(){ xecho "[$(fdate)] ${GRN}${BLD}[+]${DEF} $*"; }
warn(){ xecho "[$(fdate)] ${YLW}${BLD}[!]${DEF} $*" >&2; }
err(){ xecho "[$(fdate)] ${RED}${BLD}[-]${DEF} $*" >&2; }
dbg(){ [[ ${DEBUG:-0} -eq 1 ]] && xecho "[$(fdate)] ${MGN}[DBG]${DEF} $*" || :; }
get_drive_trans(){
  local dev="${1:?}"
  lsblk -dno TRAN "$dev" 2>&1 || echo "unknown"
}
assert_usb_dev(){
  local dev="${1:?}"
  ((cfg[no_usb_check])) && return 0
  [[ $dev == /dev/loop* ]] && return 0
  local trans
  trans=$(get_drive_trans "$dev")
  [[ $trans != usb && $trans != mmc ]] && {
    err "Device $dev is not USB/MMC (Detected: $trans). Use -U to bypass."
    cleanup
    exit 1
  }
}
assert_size(){
  local img="${1:?}" dev="${2:?}"
  ((cfg[no_size_check])) && return 0
  [[ ! -b $dev ]] && return 0
  local img_bytes dev_bytes
  img_bytes=$(stat -c%s "$img")
  dev_bytes=$(blockdev --getsize64 "$dev")
  ((img_bytes>dev_bytes)) && {
    err "Image ($((img_bytes/1024/1024))MB) exceeds target ($((dev_bytes/1024/1024))MB)."
    cleanup
    exit 1
  }
}
select_target_interactive(){
  has fzf || {
    err "fzf required for interactive selection."
    cleanup
    exit 1
  }
  log "Scanning for removable drives..."
  local selection
  selection=$(lsblk -p -d -n -o NAME,MODEL,VENDOR,SIZE,TRAN,TYPE,HOTPLUG | awk -v skip="${cfg[no_usb_check]}" 'tolower($0)~/disk/ && (skip=="1" || tolower($0)~/usb|mmc/)' | fzf --header="TARGET SELECTION (Safety: USB/MMC Only)" --prompt="Select Drive> " --with-nth=1,2,3,4)
  [[ -z $selection ]] && {
    err "No target selected."
    cleanup
    exit 1
  }
  awk '{print $1}' <<<"$selection"
}
check_deps(){
  local -a deps=(losetup parted mkfs.f2fs mkfs.vfat rsync xz blkid partprobe lsblk flock awk curl) missing=() cmd
  ((cfg[shrink])) && deps+=(e2fsck resize2fs tune2fs truncate)
  for cmd in "${deps[@]}"; do has "$cmd" || missing+=("$cmd"); done
  ((${#missing[@]}>0)) && {
    err "Missing dependencies: ${missing[*]}"
    cleanup
    exit 1
  }
}
cleanup(){
  local ret=$?
  set +e
  for ((i=${#MOUNTED_DIRS[@]}-1; i>=0; i--)); do umount -lf "${MOUNTED_DIRS[i]}" &>/dev/null; done
  [[ -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" &>/dev/null
  ((LOCK_FD>=0)) && {
    exec {LOCK_FD}>&-
    LOCK_FD=-1
  }
  [[ -f ${LOCK_FILE:-} ]] && rm -f "$LOCK_FILE"
  [[ -n ${WORKDIR:-} && -d $WORKDIR ]] && rm -rf "$WORKDIR"
  return "$ret"
}
derive_partition_paths(){
  local dev="${1:?}"
  [[ $dev =~ (nvme|mmcblk|loop) ]] && {
    BOOT_PART="${dev}p1"
    ROOT_PART="${dev}p2"
  } || {
    BOOT_PART="${dev}1"
    ROOT_PART="${dev}2"
  }
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
  err "Partitions failed to appear on $dev"
  cleanup
  exit 1
}
prepare_environment(){
  WORKDIR=$(mktemp -d -p "${TMPDIR:-/tmp}" rf2fs.XXXXXX)
  SRC_IMG="$WORKDIR/source.img"
  trap cleanup EXIT INT TERM
  sync
  sudo sh -c 'echo 3>/proc/sys/vm/drop_caches'
}
process_source(){
  [[ $SRC_PATH == dietpi ]] && {
    log "Keyword 'dietpi' detected. Using URL: $DIETPI_URL"
    SRC_PATH="$DIETPI_URL"
  }
  if [[ $SRC_PATH =~ ^https?:// ]]; then
    log "Downloading image from URL..."
    [[ $SRC_PATH == *.xz ]] && curl -Lfs --progress-bar "$SRC_PATH" | xz -dc >"$SRC_IMG" || curl -Lfs --progress-bar "$SRC_PATH" -o "$SRC_IMG" || {
      err "Download failed."
      cleanup
      exit 1
    }
    return 0
  fi
  log "Processing local source: $SRC_PATH"
  [[ -f $SRC_PATH ]] || {
    err "Source file not found."
    cleanup
    exit 1
  }
  if [[ $SRC_PATH == *.xz ]]; then
    log "Decompressing xz archive..."
    xz -dc "$SRC_PATH" >"$SRC_IMG"
  elif ((cfg[keep_source])); then
    cp --reflink=auto "$SRC_PATH" "$SRC_IMG"
  else ln "$SRC_PATH" "$SRC_IMG" 2>&1 || cp "$SRC_PATH" "$SRC_IMG"; fi
}
check_filesystem(){
  local dev="${1:?}"
  log "Checking filesystem on $dev..."
  e2fsck -pf "$dev"
  (($?<4)) && return
  warn "Filesystem error detected! Attempting recovery..."
  e2fsck -y "$dev"
  (($?<4)) && return
  e2fsck -fy -b 32768 "$dev"
  (($?<4)) && return
  err "Filesystem recovery failed (non-fatal, continuing...)"
}
shrink_source_image(){
  log "Shrinking source image before flash..."
  local parted_out partnum partstart parttype currentsize blocksize minsize extra_space partnewsize newpartend endresult
  parted_out=$(parted -ms "$SRC_IMG" unit B print) || {
    err "parted failed (non-fatal, skipping shrink)"
    return
  }
  partnum=$(awk -F: 'END{print $1}' <<<"$parted_out")
  partstart=$(awk -F: 'END{print $2}' <<<"$parted_out" | tr -d B)
  [[ -z $(parted -s "$SRC_IMG" unit B print | grep "$partstart" | grep logical) ]] && parttype="primary" || parttype="logical"
  LOOP_DEV=$(losetup -f --show -o "$partstart" "$SRC_IMG") || {
    err "Failed to setup loop device (skipping shrink)"
    return
  }
  check_filesystem "$LOOP_DEV"
  local tune_out
  tune_out=$(tune2fs -l "$LOOP_DEV" 2>&1) || {
    err "tune2fs failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }
  currentsize=$(awk -F: '/^Block count:/{gsub(" ","",$2);print $2}' <<<"$tune_out")
  blocksize=$(awk -F: '/^Block size:/{gsub(" ","",$2);print $2}' <<<"$tune_out")
  minsize=$(resize2fs -P "$LOOP_DEV" 2>&1 | awk -F: '{gsub(" ","",$2);print $2}') || {
    err "resize2fs -P failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }
  [[ $currentsize -eq $minsize ]] && {
    log "Source image already at minimum size"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }
  extra_space=$((currentsize-minsize))
  for space in 5000 1000 100; do ((extra_space>space)) && { minsize=$((minsize+space)); break; }; done
  log "Resizing source filesystem to ${minsize} blocks..."
  resize2fs -p "$LOOP_DEV" "$minsize" || {
    err "resize2fs failed (skipping shrink)"
    losetup -d "$LOOP_DEV" &>/dev/null
    return
  }
  local mnt
  mnt=$(mktemp -d)
  mount "$LOOP_DEV" "$mnt"
  log "Zeroing free space in source..."
  cat /dev/zero >"$mnt/zero_file" 2>&1 || :
  rm -f "$mnt/zero_file"
  umount "$mnt"
  rmdir "$mnt"
  partnewsize=$((minsize*blocksize))
  newpartend=$((partstart+partnewsize))
  log "Shrinking source partition..."
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
  endresult=$(parted -ms "$SRC_IMG" unit B print free | tail -1 | awk -F: '{print $2}' | tr -d B)
  log "Truncating source image to ${endresult}B..."
  truncate -s "$endresult" "$SRC_IMG" || {
    err "truncate failed (non-fatal)"
    return
  }
  msg "Source image shrunk successfully (faster flash ahead!)"
}
setup_target_device(){
  log "Preparing target: $TGT_PATH"
  LOCK_FILE="/run/lock/raspi-f2fs-${TGT_PATH//\//_}.lock"
  mkdir -p "${LOCK_FILE%/*}"
  exec {LOCK_FD}>"$LOCK_FILE" || {
    err "Cannot create lock file"
    cleanup
    exit 1
  }
  flock -n "$LOCK_FD" || {
    err "Device $TGT_PATH is in use."
    cleanup
    exit 1
  }
  assert_usb_dev "$TGT_PATH"
  assert_size "$SRC_IMG" "$TGT_PATH"
  ((cfg[dry_run])) && return 0
  warn "${RED}WARNING: ALL DATA ON $TGT_PATH WILL BE ERASED!${DEF}"
  wipefs -af "$TGT_PATH" &>/dev/null
  log "Partitioning..."
  parted -s "$TGT_PATH" mklabel msdos
  parted -s "$TGT_PATH" mkpart primary fat32 0% "${cfg[boot_size]}"
  parted -s "$TGT_PATH" mkpart primary "${cfg[boot_size]}" 100%
  parted -s "$TGT_PATH" set 1 boot on
  wait_for_partitions "$TGT_PATH"
  TGT_DEV="$TGT_PATH"
}
format_target(){
  log "Formatting filesystems..."
  ((cfg[dry_run])) && return 0
  mkfs.vfat -F32 -n BOOT "$BOOT_PART" &>/dev/null
  mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum,compression "$ROOT_PART" &>/dev/null
}
clone_data(){
  log "Cloning data (rsync)..."
  ((cfg[dry_run])) && return 0
  LOOP_DEV=$(losetup --show -f -P "$SRC_IMG")
  derive_partition_paths "$LOOP_DEV"
  mkdir -p "$WORKDIR"/{src,tgt}/{boot,root}
  mount -o ro "$BOOT_PART" "$WORKDIR/src/boot"
  MOUNTED_DIRS+=("$WORKDIR/src/boot")
  mount -o ro "$ROOT_PART" "$WORKDIR/src/root"
  MOUNTED_DIRS+=("$WORKDIR/src/root")
  derive_partition_paths "$TGT_DEV"
  mount "$BOOT_PART" "$WORKDIR/tgt/boot"
  MOUNTED_DIRS+=("$WORKDIR/tgt/boot")
  mount "$ROOT_PART" "$WORKDIR/tgt/root"
  MOUNTED_DIRS+=("$WORKDIR/tgt/root")
  log "Syncing /boot..."
  rsync -aHAX --info=progress2 "$WORKDIR/src/boot/" "$WORKDIR/tgt/boot/"
  log "Syncing / (Rootfs)..."
  rsync -aHAX --info=progress2 --exclude 'lost+found' "$WORKDIR/src/root/" "$WORKDIR/tgt/root/"
  sync
}
configure_pi_boot(){
  log "Configuring F2FS boot parameters..."
  ((cfg[dry_run])) && return 0
  local boot_uuid root_uuid cmdline fstab
  boot_uuid=$(blkid -s PARTUUID -o value "$BOOT_PART")
  root_uuid=$(blkid -s PARTUUID -o value "$ROOT_PART")
  cmdline="$WORKDIR/tgt/boot/cmdline.txt"
  fstab="$WORKDIR/tgt/root/etc/fstab"
  awk -v uuid="$root_uuid" '{line="";for(i=1;i<=NF;i++){if($i~/^root=/)$i="root=PARTUUID="uuid;else if($i~/^rootfstype=/)$i="rootfstype=f2fs";else if($i~/^init=.*init_resize\.sh/)continue;line=(line?line" ":"")$i}if(line!~/rootwait/)line=line" rootwait";if(line!~/fsck\.repair=yes/)line=line" fsck.repair=yes";print line}' "$cmdline" >"${cmdline}.tmp" && mv "${cmdline}.tmp" "$cmdline"
  cat >"$fstab" <<-EOF
	proc            /proc           proc    defaults          0       0
	PARTUUID=$boot_uuid  /boot           vfat    defaults          0       2
	PARTUUID=$root_uuid  /               f2fs    defaults,noatime  0       1
	EOF
  ((cfg[ssh])) && touch "$WORKDIR/tgt/boot/ssh"
  log "Configuration complete."
}
usage(){
  cat <<-EOF
	Usage: $(basename "$0") [OPTIONS]
	Flash Raspberry Pi image to SD card using F2FS root filesystem.
	OPTIONS:
	  -i FILE   Source image (.img, .img.xz, URL, or 'dietpi')
	  -d DEV    Target device (e.g., /dev/sdX)
	  -b SIZE   Boot partition size (default: 512M)
	  -z        Shrink source image before flash (PiShrink)
	  -s        Enable SSH
	  -k        Keep source file (don't delete if extracted)
	  -U        Disable USB/MMC safety check (Dangerous)
	  -F        Disable Size safety check
	  -n        Dry-run
	  -h        Help
EOF
  exit 0
}
while getopts "b:i:d:zsknhUF" opt; do
  case $opt in
    b) cfg[boot_size]=$OPTARG ;; i) SRC_PATH=$OPTARG ;; d) TGT_PATH=$OPTARG ;; z) cfg[shrink]=1 ;; s) cfg[ssh]=1 ;; k) cfg[keep_source]=1 ;; n) cfg[dry_run]=1 ;; U) cfg[no_usb_check]=1 ;; F) cfg[no_size_check]=1 ;; h) usage ;; *) usage ;;
  esac
done
[[ $EUID -ne 0 ]] && {
  err "This script requires root privileges (sudo)."
  cleanup
  exit 1
}
check_deps
[[ -z $SRC_PATH ]] && SRC_PATH=$(find . -maxdepth 2 \( -name "*.img*" -o -name "*.xz" \) | fzf --prompt="Select Source Image (or enter URL/dietpi)> ") && [[ -z $SRC_PATH ]] && {
  err "No source image selected."
  cleanup
  exit 1
}
[[ -z $TGT_PATH ]] && TGT_PATH=$(select_target_interactive)
prepare_environment
process_source
((cfg[shrink])) && shrink_source_image
setup_target_device
format_target
clone_data
configure_pi_boot
msg "${GRN}SUCCESS:${DEF} Flashed to $TGT_PATH with F2FS."
msg "You can now safely remove the device."
