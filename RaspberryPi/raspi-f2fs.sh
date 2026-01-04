#!/usr/bin/env bash
# raspi-f2fs.sh - Optimized Raspberry Pi F2FS Flasher
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C

# --- Config & Helpers ---
: "${BOOT_SIZE:=512M}" "${SSH:=0}" "${DRY:=0}" "${KEEP:=0}" "${NO_USB:=0}" "${NO_SZ:=0}" "${SHRINK:=0}"
DIETPI_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
die() {
  printf "%b[ERR]%b %s\n" "$R" "$X" "$*" >&2
  cleanup
  exit 1
}
log() { printf "%b[INF]%b %s\n" "$B" "$X" "$*"; }
warn() { printf "%b[WRN]%b %s\n" "$Y" "$X" "$*" >&2; }
has() { command -v "$1" &>/dev/null; }
cleanup() {
  set +e
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&-
  for d in "${MOUNTS[@]}"; do umount -lf "$d" 2>/dev/null; done
  [[ -b ${LOOP:-} ]] && losetup -d "$LOOP" 2>/dev/null
  [[ -f ${LOCK:-} ]] && rm -f "$LOCK"
  [[ -d ${WD:-} ]] && rm -rf "$WD"
}
trap cleanup EXIT INT TERM
# --- Core Logic ---
check_deps() {
  local d=(losetup parted mkfs.f2fs mkfs.vfat rsync xz blkid partprobe lsblk flock awk curl wipefs udevadm)
  ((SHRINK)) && d+=(e2fsck resize2fs tune2fs truncate)
  for c in "${d[@]}"; do has "$c" || die "Missing dependency: $c"; done
}
select_dev() {
  has fzf || die "fzf required for interactive mode"
  lsblk -pndo NAME,MODEL,SIZE,TRAN,TYPE | awk -v s="$NO_USB" 'tolower($0)~/disk/&&(s=="1"||tolower($0)~/usb|mmc/)' \
    | fzf --header="SELECT TARGET (DATA WILL BE ERASED)" --preview='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT {1}' | awk '{print $1}'
}
prep_src() {
  WD=$(mktemp -d)
  IMG="$WD/src.img"
  [[ "$SRC" == "dietpi" ]] && SRC="$DIETPI_URL"
  if [[ $SRC =~ ^https?:// ]]; then
    log "Downloading $SRC..."
    curl -Lfs --progress-bar "$SRC" | { [[ $SRC == *.xz ]] && xz -dc || cat; } >"$IMG" || die "Download failed"
  elif [[ -f $SRC ]]; then
    log "Using local: $SRC"
    [[ $SRC == *.xz ]] && xz -dc "$SRC" >"$IMG" || { ((KEEP)) && cp --reflink=auto "$SRC" "$IMG" || cp "$SRC" "$IMG"; }
  else die "Invalid source: $SRC"; fi
}

shrink_img() {
  log "Shrinking image..."
  local p_out
  p_out=$(parted -ms "$IMG" unit B print)
  local start
  start=$(awk -F: 'END{print $2}' <<<"$p_out" | tr -d B)
  local num
  num=$(awk -F: 'END{print $1}' <<<"$p_out")
  LOOP=$(losetup -f --show -o "$start" "$IMG") || die "Loop setup failed"
  e2fsck -pf "$LOOP" || e2fsck -fy "$LOOP" || die "FS check failed"
  local sz_blk sz_cur sz_min tune_out
  tune_out=$(tune2fs -l "$LOOP")
  read -r _ _ _ sz_blk < <(grep "Block size" <<<"$tune_out")
  read -r _ _ _ sz_cur < <(grep "Block count" <<<"$tune_out")
  sz_min=$(resize2fs -P "$LOOP" 2>/dev/null | awk -F: '{print $2}')
  sz_min=$((sz_min + 5000)) # Safety buffer
  if ((sz_cur > sz_min)); then
    resize2fs -p "$LOOP" "$sz_min" || die "Resize failed"
    local end_b=$((start + sz_min * sz_blk))
    losetup -d "$LOOP"
    LOOP=""
    parted -s "$IMG" rm "$num" mkpart primary "$start"B "$end_b"B
    truncate -s "$end_b" "$IMG"
    log "Shrunk to $((end_b / 1024 / 1024))MB"
  else
    log "Image already minimal"
    losetup -d "$LOOP"
    LOOP=""
  fi
}

setup_tgt() {
  LOCK="/run/lock/rf2fs-${TGT//\//_}.lock"
  mkdir -p "${LOCK%/*}"
  exec {LOCK_FD}>"$LOCK" && flock -n "$LOCK_FD" || die "Device $TGT locked"
  ((NO_USB)) || [[ $(lsblk -dno TRAN "$TGT") =~ ^(usb|mmc)$ ]] || die "$TGT is not USB/MMC (Use -U to force)"
  ((NO_SZ)) || [[ $(stat -c%s "$IMG") -lt $(blockdev --getsize64 "$TGT") ]] || die "Image too large for target"
  ((DRY)) && return
  log "Wiping and partitioning $TGT..."
  wipefs -af "$TGT"
  parted -s "$TGT" mklabel msdos mkpart primary fat32 0% "$BOOT_SIZE" mkpart primary "$BOOT_SIZE" 100% set 1 boot on
  partprobe "$TGT"
  udevadm settle
  sleep 1
  [[ $TGT =~ nvme|mmcblk|loop ]] && local p="p" || local p=""
  BP="${TGT}${p}1"
  RP="${TGT}${p}2"
  for i in {1..30}; do
    [[ -b $BP && -b $RP ]] && break
    sleep 0.5
  done
  [[ -b $BP && -b $RP ]] || die "Partitions missing"
  mkfs.vfat -F32 -n BOOT "$BP" >/dev/null
  mkfs.f2fs -f -l ROOT -O extra_attr,inode_checksum,sb_checksum,compression "$RP" >/dev/null
}
clone() {
  log "Cloning data..."
  ((DRY)) && return
  LOOP=$(losetup --show -f -P "$IMG")
  MOUNTS=()
  [[ $LOOP =~ nvme|mmcblk|loop ]] && local p="p" || local p=""
  mkdir -p "$WD"/{s,t}/{b,r}
  mount -o ro "${LOOP}${p}1" "$WD/s/b"
  MOUNTS+=("$WD/s/b")
  mount -o ro "${LOOP}${p}2" "$WD/s/r"
  MOUNTS+=("$WD/s/r")
  mount "$BP" "$WD/t/b"
  MOUNTS+=("$WD/t/b")
  mount "$RP" "$WD/t/r"
  MOUNTS+=("$WD/t/r")
  rsync -aHAX --info=progress2 "$WD/s/b/" "$WD/t/b/"
  rsync -aHAX --info=progress2 --exclude 'lost+found' "$WD/s/r/" "$WD/t/r/"
  sync
  log "Configuring boot..."
  local buuid
  buuid=$(blkid -s PARTUUID -o value "$BP")
  local ruuid
  ruuid=$(blkid -s PARTUUID -o value "$RP")
  sed -i -e "s/root=[^ ]*/root=PARTUUID=$ruuid rootfstype=f2fs/" \
    -e 's/init=[^ ]*init_resize.sh[^ ]*//' "$WD/t/b/cmdline.txt"
  echo -e "proc /proc proc defaults 0 0\nPARTUUID=$buuid /boot vfat defaults 0 2\nPARTUUID=$ruuid / f2fs defaults,noatime 0 1" >"$WD/t/r/etc/fstab"
  ((SSH)) && touch "$WD/t/b/ssh" && log "SSH enabled"
}
usage() {
  cat <<EOF
Usage: sudo ${0##*/} [-i IMG|URL|dietpi] [-d DEV] [-b SIZE] [-zsknUF]
  -i  Source (default: interactive)
  -d  Target (default: interactive)
  -b  Boot size (def: 512M)
  -z  Shrink image
  -s  Enable SSH
  -k  Keep source
  -n  Dry run
  -U  No USB check
  -F  No size check
EOF
  exit 0
}
# --- Main ---
((EUID == 0)) || die "Root required"
while getopts "b:i:d:zsknhUF" o; do
  case $o in b) BOOT_SIZE=$OPTARG ;; i) SRC=$OPTARG ;; d) TGT=$OPTARG ;; z) SHRINK=1 ;; s) SSH=1 ;; k) KEEP=1 ;; n) DRY=1 ;; U) NO_USB=1 ;; F) NO_SZ=1 ;; *) usage ;; esac
done
check_deps
[[ -z ${SRC:-} ]] && SRC=$(find . -maxdepth 2 \( -name "*.img*" -o -name "*.xz" \) 2>/dev/null | fzf --prompt="Source> " --preview='ls -lh {}' | awk '{print $1}')
[[ -z ${SRC:-} ]] && die "No source selected"
[[ -z ${TGT:-} ]] && TGT=$(select_dev)
[[ -z ${TGT:-} ]] && die "No target selected"
prep_src
((SHRINK)) && shrink_img
setup_tgt
clone
log "Done! Flashed to $TGT"
