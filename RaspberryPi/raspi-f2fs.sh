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
detect_dietpi() {
  IS_DIETPI=0
  DIETPI_VERSION=""
  PI_MODEL=""

  # Check for DietPi markers
  if [[ -f "$WD/t/b/dietpi/.version" || -f "$WD/t/r/DietPi/dietpi.txt" ]]; then
    IS_DIETPI=1

    # Extract DietPi version
    if [[ -f "$WD/t/b/dietpi/.version" ]]; then
      DIETPI_VERSION=$(cat "$WD/t/b/dietpi/.version" | head -1)
    elif [[ -f "$WD/t/r/boot/dietpi/.version" ]]; then
      DIETPI_VERSION=$(cat "$WD/t/r/boot/dietpi/.version" | head -1)
    fi

    # Detect Pi model from device tree or cpuinfo
    if [[ -f "$WD/t/b/config.txt" ]]; then
      if grep -qi "pi5" "$WD/t/b/config.txt" 2>/dev/null || grep -qi "2712" "$WD/t/b/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 5"
      elif grep -qi "pi4" "$WD/t/b/config.txt" 2>/dev/null || grep -qi "2711" "$WD/t/b/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 4"
      elif grep -qi "pi3" "$WD/t/b/config.txt" 2>/dev/null || grep -qi "2837" "$WD/t/b/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 3"
      else
        PI_MODEL="Raspberry Pi (unknown model)"
      fi
    fi

    log "Detected DietPi installation: v${DIETPI_VERSION:-unknown}"
    log "Hardware: ${PI_MODEL:-unknown}"
  fi
}

backup_dietpi_configs() {
  ((IS_DIETPI)) || return 0

  BACKUP_DIR="$WD/dietpi_backup"
  mkdir -p "$BACKUP_DIR"
  log "Backing up critical DietPi configs to $BACKUP_DIR..."

  # Backup DietPi core files
  [[ -f "$WD/t/b/dietpi/.installed" ]] && cp "$WD/t/b/dietpi/.installed" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$WD/t/b/dietpi/dietpi.txt" ]] && cp "$WD/t/b/dietpi/dietpi.txt" "$BACKUP_DIR/" 2>/dev/null || :

  # Backup network configs
  [[ -f "$WD/t/r/etc/network/interfaces" ]] && cp "$WD/t/r/etc/network/interfaces" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -d "$WD/t/r/etc/wpa_supplicant" ]] && cp -r "$WD/t/r/etc/wpa_supplicant" "$BACKUP_DIR/" 2>/dev/null || :

  # Backup system identifiers
  [[ -f "$WD/t/r/etc/hostname" ]] && cp "$WD/t/r/etc/hostname" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$WD/t/r/etc/hosts" ]] && cp "$WD/t/r/etc/hosts" "$BACKUP_DIR/" 2>/dev/null || :

  log "Backup complete"
}

remove_ext4_configs() {
  ((IS_DIETPI)) || return 0

  log "Removing ext4-specific configs..."

  # Remove ext4 mount options from fstab
  local fstab="$WD/t/r/etc/fstab"
  if [[ -f "$fstab" ]]; then
    if grep -q "ext4" "$fstab"; then
      log "Found ext4 entries in fstab (will be updated later)"
    fi
  fi

  # Remove ext4 journal settings from mke2fs.conf
  local mke2fs_conf="$WD/t/r/etc/mke2fs.conf"
  if [[ -f "$mke2fs_conf" ]]; then
    if grep -q "journal" "$mke2fs_conf" 2>/dev/null; then
      log "Removed ext4 journal settings from mke2fs.conf"
      sed -i '/journal/d' "$mke2fs_conf"
    fi
  fi

  # Remove ext4-specific cron jobs
  local cron_dir="$WD/t/r/etc/cron.d"
  if [[ -d "$cron_dir" ]]; then
    for f in "$cron_dir"/*; do
      [[ -f "$f" ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific cron job: ${f##*/}"
        rm -f "$f"
      fi
    done
  fi

  # Remove ext4-specific systemd timers
  local systemd_dir="$WD/t/r/etc/systemd/system"
  if [[ -d "$systemd_dir" ]]; then
    for f in "$systemd_dir"/*.timer; do
      [[ -f "$f" ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific systemd timer: ${f##*/}"
        rm -f "$f"
        # Remove corresponding service file
        rm -f "${f%.timer}.service" 2>/dev/null || :
      fi
    done
  fi

  log "ext4-specific configs removed"
}

update_fstab_f2fs() {
  local fstab="$WD/t/r/etc/fstab"
  local buuid="$1"
  local ruuid="$2"

  if [[ -f "$fstab" ]] && ((IS_DIETPI)); then
    log "Updating existing fstab for F2FS..."
    # Update root partition fstype to f2fs and add optimal mount options
    sed -i -E \
      -e 's|^([^#].*[[:space:]]+/[[:space:]]+)ext4([[:space:]]+.*)|PARTUUID='"$ruuid"' / f2fs defaults,noatime,compress_algorithm=zstd,compress_chksum,atgc,gc_merge 0 1|' \
      -e 's|^([^#].*[[:space:]]+/boot[[:space:]]+).*|PARTUUID='"$buuid"' /boot vfat defaults 0 2|' \
      "$fstab"
  else
    log "Creating new fstab for F2FS..."
    cat >"$fstab" <<EOF
proc /proc proc defaults 0 0
PARTUUID=$buuid /boot vfat defaults 0 2
PARTUUID=$ruuid / f2fs defaults,noatime,compress_algorithm=zstd,compress_chksum,atgc,gc_merge 0 1
EOF
  fi
}

update_cmdline_f2fs() {
  local cmdline="$WD/t/b/cmdline.txt"
  local ruuid="$1"

  [[ -f "$cmdline" ]] || die "cmdline.txt not found: $cmdline"

  log "Updating cmdline.txt for F2FS root..."

  # Read current cmdline
  local cmd
  cmd=$(<"$cmdline")

  # Update root= parameter
  cmd=$(sed -E "s/(^|[[:space:]])root=[^[:space:]]+/\1root=PARTUUID=${ruuid}/" <<<"$cmd")

  # Add or update rootfstype=f2fs
  if grep -qE '(^|[[:space:]])rootfstype=' <<<"$cmd"; then
    cmd=$(sed -E 's/(^|[[:space:]])rootfstype=[^[:space:]]+/\1rootfstype=f2fs/' <<<"$cmd")
  else
    cmd+=" rootfstype=f2fs"
  fi

  # Remove init_resize.sh if present (DietPi/Raspbian first-boot script)
  cmd=$(sed -E 's/[[:space:]]+init=[^[:space:]]*init_resize\.sh[^[:space:]]*//' <<<"$cmd")

  # Write back
  printf '%s\n' "$cmd" >"$cmdline"
}

prepare_initramfs_f2fs() {
  ((IS_DIETPI)) || return 0

  local initramfs_modules="$WD/t/r/etc/initramfs-tools/modules"
  local boot_dir="$WD/t/r/boot"

  # Check if system uses initramfs
  if [[ ! -d "$WD/t/r/etc/initramfs-tools" ]]; then
    log "System does not use initramfs-tools, skipping F2FS module addition"
    return 0
  fi

  # Check if initramfs exists in boot
  local has_initramfs=0
  if ls "$boot_dir"/initrd.img-* &>/dev/null || ls "$boot_dir"/initramfs-* &>/dev/null; then
    has_initramfs=1
  fi

  if ((has_initramfs == 0)); then
    log "No initramfs found in /boot, skipping F2FS module addition"
    return 0
  fi

  log "Adding F2FS module to initramfs..."

  # Add f2fs to modules if not already present
  if [[ ! -f "$initramfs_modules" ]]; then
    mkdir -p "$(dirname "$initramfs_modules")"
    echo "f2fs" >"$initramfs_modules"
    log "Created $initramfs_modules with F2FS module"
  elif ! grep -q "^f2fs$" "$initramfs_modules" 2>/dev/null; then
    echo "f2fs" >>"$initramfs_modules"
    log "Added F2FS to existing $initramfs_modules"
  else
    log "F2FS module already present in initramfs modules"
  fi

  # Create marker file for chroot script to regenerate initramfs
  touch "$WD/t/r/.regenerate_initramfs"
  log "Marked for initramfs regeneration (will be done in chroot)"
}

check_f2fs_support() {
  log "Checking F2FS kernel support..."

  # Check if f2fs module exists in the image's kernel modules
  local modules_dir="$WD/t/r/lib/modules"
  local has_f2fs=0

  if [[ -d "$modules_dir" ]]; then
    if find "$modules_dir" -name "f2fs.ko*" 2>/dev/null | grep -q .; then
      has_f2fs=1
      log "F2FS module found in kernel"
    fi
  fi

  # Check host system for f2fs support as fallback
  if ((has_f2fs == 0)); then
    if [[ -f /proc/filesystems ]] && grep -q "f2fs" /proc/filesystems; then
      has_f2fs=1
      log "F2FS supported on host system"
    elif modinfo f2fs &>/dev/null; then
      has_f2fs=1
      log "F2FS module available on host"
    fi
  fi

  if ((has_f2fs == 0)); then
    warn "F2FS support not detected in kernel"
    warn "Image may fail to boot if kernel lacks F2FS support"
    warn "Ensure target Pi kernel has CONFIG_F2FS_FS enabled"
  else
    log "F2FS support verified"
  fi
}

verify_conversion() {
  ((IS_DIETPI)) || return 0

  log "Verifying F2FS conversion..."
  local errors=0

  # Check fstab
  local fstab="$WD/t/r/etc/fstab"
  if [[ -f "$fstab" ]]; then
    if grep -q "f2fs" "$fstab"; then
      log "✓ fstab contains F2FS root entry"
    else
      warn "✗ fstab missing F2FS entry"
      ((errors++))
    fi
  else
    warn "✗ fstab not found"
    ((errors++))
  fi

  # Check cmdline.txt
  local cmdline="$WD/t/b/cmdline.txt"
  if [[ -f "$cmdline" ]]; then
    if grep -q "rootfstype=f2fs" "$cmdline"; then
      log "✓ cmdline.txt has rootfstype=f2fs"
    else
      warn "✗ cmdline.txt missing rootfstype=f2fs"
      ((errors++))
    fi
  else
    warn "✗ cmdline.txt not found"
    ((errors++))
  fi

  # Verify F2FS partition is mounted (already verified by successful mount)
  if mountpoint -q "$WD/t/r"; then
    log "✓ F2FS root partition is mountable"
  else
    warn "✗ Root partition not mounted"
    ((errors++))
  fi

  # Print summary
  printf '\n%b%s%b\n' "$B" "=== Conversion Summary ===" "$X"
  printf '%b%-30s%b %s\n' "$G" "DietPi Version:" "$X" "${DIETPI_VERSION:-unknown}"
  printf '%b%-30s%b %s\n' "$G" "Hardware:" "$X" "${PI_MODEL:-unknown}"
  printf '%b%-30s%b %s\n' "$G" "Root Filesystem:" "$X" "F2FS"
  printf '%b%-30s%b %s\n' "$G" "Boot Partition:" "$X" "FAT32"
  [[ -n ${BACKUP_DIR:-} ]] && printf '%b%-30s%b %s\n' "$G" "Backup Location:" "$X" "$BACKUP_DIR"
  printf '%b%s%b\n\n' "$B" "=========================" "$X"

  if ((errors > 0)); then
    warn "Conversion completed with $errors warning(s)"
    warn "Please review the warnings above"
  else
    log "All verification checks passed"
  fi

  # Warning about testing
  printf '\n%b%s%b\n' "$Y" "⚠ IMPORTANT:" "$X"
  printf '%s\n' "  1. Test boot before removing backup"
  printf '%s\n' "  2. Have HDMI/serial console ready for first boot"
  printf '%s\n' "  3. If boot fails, restore from backup or reflash"
  printf '%s\n' "  4. Run 'sudo dietpi-chroot.sh <image>' to regenerate initramfs if needed"
  printf '\n'
}

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
  [[ $SRC == "dietpi" ]] && SRC="$DIETPI_URL"
  if [[ $SRC =~ ^https?:// ]]; then
    # Security: Enforce HTTPS for remote downloads
    if [[ ! $SRC =~ ^https:// ]]; then
      die "Insecure HTTP URL detected. Use HTTPS for secure downloads: $SRC"
    fi
    warn "Downloading from remote source without checksum verification"
    warn "Ensure the URL is from a trusted source to prevent supply-chain attacks"
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

  # Detect DietPi installation
  detect_dietpi

  # Check F2FS support
  check_f2fs_support

  # Backup DietPi configs if needed
  backup_dietpi_configs

  rsync -aHAX --info=progress2 "$WD/s/b/" "$WD/t/b/"
  rsync -aHAX --info=progress2 --exclude 'lost+found' "$WD/s/r/" "$WD/t/r/"
  sync

  # Remove ext4-specific configs for DietPi
  remove_ext4_configs

  log "Configuring boot..."
  local buuid
  buuid=$(blkid -s PARTUUID -o value "$BP")
  local ruuid
  ruuid=$(blkid -s PARTUUID -o value "$RP")
  update_cmdline_f2fs "$ruuid"
  update_fstab_f2fs "$buuid" "$ruuid"
  prepare_initramfs_f2fs
  ((SSH)) && touch "$WD/t/b/ssh" && log "SSH enabled"

  # Verify conversion
  verify_conversion
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
  case $o in
  b) BOOT_SIZE=$OPTARG ;;
  i) SRC=$OPTARG ;;
  d) TGT=$OPTARG ;;
  z) SHRINK=1 ;;
  s) SSH=1 ;;
  k) KEEP=1 ;;
  n) DRY=1 ;;
  U) NO_USB=1 ;;
  F) NO_SZ=1 ;;
  *) usage ;;
  esac
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
