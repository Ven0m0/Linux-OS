#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C
has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf '%s\n' "$@"; }
log(){ printf '%s\n' "$@" >&2; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }

need(){ has "$1" || die "Missing dependency: $1"; }

cleanup(){
  set +e
  [[ -n "${SRC_MNT_ROOT:-}" ]] && mountpoint -q "$SRC_MNT_ROOT" && umount -R "$SRC_MNT_ROOT"
  [[ -n "${SRC_MNT_BOOT:-}" ]] && mountpoint -q "$SRC_MNT_BOOT" && umount -R "$SRC_MNT_BOOT"
  [[ -n "${DST_MNT_ROOT:-}" ]] && mountpoint -q "$DST_MNT_ROOT" && umount -R "$DST_MNT_ROOT"
  [[ -n "${DST_MNT_BOOT:-}" ]] && mountpoint -q "$DST_MNT_BOOT" && umount -R "$DST_MNT_BOOT"
  [[ -n "${LOOP_SRC:-}" ]] && losetup -d "$LOOP_SRC" &>/dev/null
  [[ -n "${LOOP_DST:-}" ]] && losetup -d "$LOOP_DST" &>/dev/null
  [[ -n "${WORKDIR:-}" && -d "${WORKDIR:-}" ]] && rm -rf -- "$WORKDIR"
}
trap cleanup EXIT

usage(){
  cat <<'EOF'
Usage:
  f2fs-new.sh [OPTIONS]

Options:
  --src URL|FILE      Source image (URL or local file)
  --out FILE          Output image path
  --device DEV        Flash to device instead of creating image
  --root-label LABEL  Root partition label (default: dietpi-root)
  --root-opts "opts"  F2FS mount options
  -i, --interactive   Interactive mode with fzf selection
  -h, --help          Show this help

Defaults:
  Source: https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz
  Output: ./DietPi_RPi234-ARMv8-Trixie_f2fs.img
  Label: dietpi-root
  Options: compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime

Examples:
  # Download and convert DietPi (interactive)
  sudo ./f2fs-new.sh -i

  # Use local image file
  sudo ./f2fs-new.sh --src ~/DietPi.img.xz --out ~/dietpi-f2fs.img

  # Flash directly to device
  sudo ./f2fs-new.sh --src ~/DietPi.img.xz --device /dev/mmcblk0

  # Use custom F2FS options
  sudo ./f2fs-new.sh --out ~/custom.img --root-opts "compress_algorithm=lz4"
EOF
}

select_source(){
  has fzf || die "fzf required for interactive mode. Install: sudo pacman -S fzf"

  msg "Select source image:\n"
  local -a choices=(
    "1|Download DietPi Trixie (latest)"
    "2|Local image file"
    "3|Custom URL"
  )

  local choice
  choice=$(printf '%s\n' "${choices[@]}" | fzf --height 10 --prompt="Source> " --with-nth=2 -d'|' | cut -d'|' -f1)

  case "$choice" in
    1) SRC_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz";;
    2)
      SRC_URL=$(find . -maxdepth 3 \( -name "*.img" -o -name "*.img.xz" \) 2>/dev/null \
        | fzf --prompt="Select image> " --preview='ls -lh {}' || die "No image selected")
      ;;
    3)
      printf 'Enter URL: '
      read -r SRC_URL
      [[ -n $SRC_URL ]] || die "No URL provided"
      ;;
    *) die "No source selected";;
  esac

  log "Source: $SRC_URL\n"
}

select_output(){
  has fzf || die "fzf required for interactive mode"

  msg "Select output:\n"
  local -a choices=(
    "1|Create image file"
    "2|Flash to device"
  )

  local choice
  choice=$(printf '%s\n' "${choices[@]}" | fzf --height 10 --prompt="Output> " --with-nth=2 -d'|' | cut -d'|' -f1)

  case "$choice" in
    1)
      printf 'Output image path [%s]: ' "$OUT_IMG"
      read -r user_out
      [[ -n $user_out ]] && OUT_IMG="$user_out"
      OUTPUT_DEVICE=""
      ;;
    2)
      OUTPUT_DEVICE=$(lsblk -pndo NAME,MODEL,SIZE,TRAN,TYPE | awk 'tolower($0)~/disk/&&tolower($0)~/usb|mmc/' \
        | fzf --prompt="Select device (DATA WILL BE ERASED)> " --preview='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT {1}' \
        | awk '{print $1}' || die "No device selected")
      OUT_IMG=""
      log "Device: $OUTPUT_DEVICE\n"
      ;;
    *) die "No output selected";;
  esac
}

SRC_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"
OUT_IMG="./DietPi_RPi234-ARMv8-Trixie_f2fs.img"
ROOT_LABEL="dietpi-root"
ROOT_OPTS="compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime"
INTERACTIVE=0
OUTPUT_DEVICE=""

while (($#)); do
  case "$1" in
    --src) SRC_URL="${2:-}"; shift 2;;
    --out) OUT_IMG="${2:-}"; shift 2;;
    --device) OUTPUT_DEVICE="${2:-}"; OUT_IMG=""; shift 2;;
    --root-label) ROOT_LABEL="${2:-}"; shift 2;;
    --root-opts) ROOT_OPTS="${2:-}"; shift 2;;
    -i|--interactive) INTERACTIVE=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

if ((INTERACTIVE)); then
  select_source
  select_output
fi

need curl
need xz
need losetup
need parted
need rsync
need blkid
need mount
need umount
need mkfs.vfat
need mkfs.f2fs
need e2fsck
need resize2fs
need sed
need grep
need awk

remove_ext4_configs(){
  local root_mnt="$1"

  log "Removing ext4-specific configs...\n"

  # Remove ext4 journal settings from mke2fs.conf
  local mke2fs_conf="$root_mnt/etc/mke2fs.conf"
  if [[ -f "$mke2fs_conf" ]]; then
    if grep -q "journal" "$mke2fs_conf" 2>/dev/null; then
      log "Removed ext4 journal settings from mke2fs.conf\n"
      sed -i '/journal/d' "$mke2fs_conf"
    fi
  fi

  # Remove ext4-specific cron jobs
  local cron_dir="$root_mnt/etc/cron.d"
  if [[ -d "$cron_dir" ]]; then
    for f in "$cron_dir"/*; do
      [[ -f "$f" ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific cron job: ${f##*/}\n"
        rm -f "$f"
      fi
    done
  fi

  # Remove ext4-specific systemd timers
  local systemd_dir="$root_mnt/etc/systemd/system"
  if [[ -d "$systemd_dir" ]]; then
    for f in "$systemd_dir"/*.timer; do
      [[ -f "$f" ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific systemd timer: ${f##*/}\n"
        rm -f "$f"
        rm -f "${f%.timer}.service" 2>/dev/null || :
      fi
    done
  fi

  log "ext4-specific configs removed\n"
}

add_f2fs_to_initramfs(){
  local root_mnt="$1"

  local initramfs_modules="$root_mnt/etc/initramfs-tools/modules"
  local boot_dir="$root_mnt/boot"

  # Check if system uses initramfs
  if [[ ! -d "$root_mnt/etc/initramfs-tools" ]]; then
    log "System does not use initramfs-tools, skipping F2FS module addition\n"
    return 0
  fi

  # Check if initramfs exists in boot
  local has_initramfs=0
  if ls "$boot_dir"/initrd.img-* &>/dev/null || ls "$boot_dir"/initramfs-* &>/dev/null; then
    has_initramfs=1
  fi

  if ((has_initramfs == 0)); then
    log "No initramfs found in /boot, skipping F2FS module addition\n"
    return 0
  fi

  log "Adding F2FS module to initramfs...\n"

  # Add f2fs to modules if not already present
  if [[ ! -f "$initramfs_modules" ]]; then
    mkdir -p "$(dirname "$initramfs_modules")"
    echo "f2fs" >"$initramfs_modules"
    log "Created $initramfs_modules with F2FS module\n"
  elif ! grep -q "^f2fs$" "$initramfs_modules" 2>/dev/null; then
    echo "f2fs" >>"$initramfs_modules"
    log "Added F2FS to existing $initramfs_modules\n"
  else
    log "F2FS module already present in initramfs modules\n"
  fi

  # Create marker for chroot script
  touch "$root_mnt/.regenerate_initramfs"
  log "Marked for initramfs regeneration (run dietpi-chroot.sh on the output image)\n"
}

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

# Handle source (URL or local file)
if [[ $SRC_URL =~ ^https?:// ]]; then
  src_archive="${SRC_URL##*/}"
  log "Downloading: $SRC_URL\n"
  curl -fL --retry 5 --retry-delay 2 -o "$src_archive" "$SRC_URL"

  log "Decompressing xz...\n"
  xz -dk "$src_archive"
  SRC_IMG="${src_archive%.xz}"
  [[ -f "$SRC_IMG" ]] || die "Decompressed .img not found: $SRC_IMG"
elif [[ -f $SRC_URL ]]; then
  log "Using local file: $SRC_URL\n"
  if [[ $SRC_URL == *.xz ]]; then
    log "Decompressing xz...\n"
    xz -dc "$SRC_URL" > "source.img"
    SRC_IMG="source.img"
  else
    SRC_IMG="$(readlink -f "$SRC_URL")"
  fi
else
  die "Source not found: $SRC_URL"
fi

# Prepare output destination
if [[ -n $OUTPUT_DEVICE ]]; then
  # Flash to device mode
  [[ -b $OUTPUT_DEVICE ]] || die "Device not found: $OUTPUT_DEVICE"
  log "Will flash to device: $OUTPUT_DEVICE\n"
  OUT_IMG="$OUTPUT_DEVICE"
else
  # Create image file mode
  OUT_IMG="$(readlink -f -- "$OUT_IMG")"
  log "Copying to output image: $OUT_IMG\n"
  cp -f -- "$SRC_IMG" "$OUT_IMG"
fi

# Attach both images (source read-only, destination writable)
LOOP_SRC="$(losetup --find --show --partscan --read-only "$SRC_IMG")"
LOOP_DST="$(losetup --find --show --partscan "$OUT_IMG")"
log "Source loop: $LOOP_SRC\n"
log "Dest loop:   $LOOP_DST\n"

SRC_BOOT="${LOOP_SRC}p1"
SRC_ROOT="${LOOP_SRC}p2"
DST_BOOT="${LOOP_DST}p1"
DST_ROOT="${LOOP_DST}p2"
[[ -b "$SRC_BOOT" && -b "$SRC_ROOT" ]] || die "Source partitions missing (expected p1,p2)"
[[ -b "$DST_BOOT" && -b "$DST_ROOT" ]] || die "Dest partitions missing (expected p1,p2)"

src_root_type="$(blkid -o value -s TYPE "$SRC_ROOT" || true)"
dst_root_type="$(blkid -o value -s TYPE "$DST_ROOT" || true)"
[[ "$src_root_type" == "ext4" ]] || die "Expected source rootfs ext4, got: ${src_root_type:-unknown}"
[[ "$dst_root_type" == "ext4" ]] || die "Expected dest rootfs ext4 before conversion, got: ${dst_root_type:-unknown}"

read_part_geom(){
  local disk="$1" partnum="$2"
  parted -m -s "$disk" unit s print | awk -F: -v p="$partnum" '$1==p {gsub(/s/,"",$2); gsub(/s/,"",$3); print $2, $3}'
}

geom="$(read_part_geom "$LOOP_DST" 2)"
[[ -n "$geom" ]] || die "Failed reading dest partition 2 geometry"
read -r ROOT_START ROOT_END <<<"$geom"
log "Dest root geometry (sectors): start=$ROOT_START end=$ROOT_END\n"

# Mount source partitions for later
SRC_MNT_BOOT="$WORKDIR/src_boot"
SRC_MNT_ROOT="$WORKDIR/src_root"
mkdir -p "$SRC_MNT_BOOT" "$SRC_MNT_ROOT"
mount "$SRC_BOOT" "$SRC_MNT_BOOT"
mount -o ro "$SRC_ROOT" "$SRC_MNT_ROOT"

# Unmount dest root so we can delete/recreate p2
# (It shouldn't be mounted, but make it explicit if user ran script twice)
DST_MNT_ROOT="$WORKDIR/dst_root"
DST_MNT_BOOT="$WORKDIR/dst_boot"
mkdir -p "$DST_MNT_ROOT" "$DST_MNT_BOOT"
mount "$DST_BOOT" "$DST_MNT_BOOT"

log "e2fsck/resize2fs preflight on dest ext4 root...\n"
e2fsck -fy "$DST_ROOT" >/dev/null
resize2fs -M "$DST_ROOT" >/dev/null || true

log "Recreating dest partition 2 as f2fs...\n"
parted -s "$LOOP_DST" rm 2
parted -s "$LOOP_DST" unit s mkpart primary "$ROOT_START" "$ROOT_END"
partprobe "$LOOP_DST" || true

# Reattach dest loop to refresh partition nodes
losetup -d "$LOOP_DST" &>/dev/null
LOOP_DST="$(losetup --find --show --partscan "$OUT_IMG")"
DST_BOOT="${LOOP_DST}p1"
DST_ROOT="${LOOP_DST}p2"
[[ -b "$DST_ROOT" ]] || die "Dest root partition missing after recreate: $DST_ROOT"

log "Formatting dest root as f2fs (label=$ROOT_LABEL)...\n"
mkfs.f2fs -f -l "$ROOT_LABEL" "$DST_ROOT" >/dev/null

log "Mounting dest f2fs root...\n"
mount "$DST_ROOT" "$DST_MNT_ROOT"

log "Copying rootfs ext4 -> f2fs (rsync)...\n"
rsync -aHAX --numeric-ids --info=progress2 \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
  "$SRC_MNT_ROOT"/ "$DST_MNT_ROOT"/

# Remove ext4-specific configs
remove_ext4_configs "$DST_MNT_ROOT"

# Add F2FS to initramfs
add_f2fs_to_initramfs "$DST_MNT_ROOT"

# Patch fstab (minimal)
FSTAB="$DST_MNT_ROOT/etc/fstab"
if [[ -f "$FSTAB" ]]; then
  log "Patching /etc/fstab root fstype -> f2fs...\n"
  # Change only the line that mounts /
  # Works whether it’s UUID=..., PARTUUID=..., /dev/mmcblk0p2, etc.
  # Replace the third column (fstype) for the / mount.
  awk '
    BEGIN{OFS="\t"}
    $0 ~ /^[[:space:]]*#/ {print; next}
    NF < 4 {print; next}
    $2 == "/" {$3="f2fs"; print; next}
    {print}
  ' "$FSTAB" >"$FSTAB.tmp" && mv -f -- "$FSTAB.tmp" "$FSTAB"
fi

# Patch cmdline.txt in dest /boot (Pi firmware reads /boot)
CMDLINE="$DST_MNT_BOOT/cmdline.txt"
[[ -f "$CMDLINE" ]] || die "Missing dest cmdline.txt: $CMDLINE"

ROOT_UUID="$(blkid -o value -s UUID "$DST_ROOT")"
[[ -n "$ROOT_UUID" ]] || die "Failed to read UUID of dest f2fs root"

log "Patching /boot/cmdline.txt root=UUID=..., rootfstype=f2fs, rootflags=...\n"
cmd="$(<"$CMDLINE")"
cmd="${cmd//$'\n'/ }"

cmd="$(sed -E "s/(^|[[:space:]])root=[^[:space:]]+/\1root=UUID=${ROOT_UUID}/" <<<"$cmd")"
if grep -qE '(^|[[:space:]])rootfstype=' <<<"$cmd"; then
  cmd="$(sed -E 's/(^|[[:space:]])rootfstype=[^[:space:]]+/\1rootfstype=f2fs/' <<<"$cmd")"
else
  cmd+=" rootfstype=f2fs"
fi
if grep -qE '(^|[[:space:]])rootflags=' <<<"$cmd"; then
  cmd="$(sed -E "s/(^|[[:space:]])rootflags=[^[:space:]]+/\1rootflags=${ROOT_OPTS}/" <<<"$cmd")"
else
  cmd+=" rootflags=${ROOT_OPTS}"
fi

printf '%s\n' "$cmd" >"$CMDLINE"

# Basic warning: fsck.f2fs may not exist; not fatal for boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "WARN: fsck.f2fs not found in rootfs. Boot should still work; fsck service (if any) may complain.\n"
fi

sync
umount -R "$DST_MNT_ROOT"
umount -R "$DST_MNT_BOOT"
umount -R "$SRC_MNT_ROOT"
umount -R "$SRC_MNT_BOOT"

log "Done.\n"

if [[ -n $OUTPUT_DEVICE ]]; then
  log "Flashed to device: $OUTPUT_DEVICE\n"
  log "Next steps:\n"
  log "  1. Remove SD card and insert into Raspberry Pi\n"
  log "  2. Optional: Run dietpi-chroot.sh on mounted card to regenerate initramfs\n"
  log "  3. Boot with HDMI/serial console ready\n"
else
  log "Output image: $OUT_IMG\n"
  log "Next steps:\n"
  log "  1. Optional: sudo ./RaspberryPi/dietpi-chroot.sh '$OUT_IMG'\n"
  log "  2. Flash: sudo dd if='$OUT_IMG' of=/dev/mmcblk0 bs=4M conv=fsync status=progress\n"
  log "  3. Boot with HDMI/serial console ready\n"
fi

log "\nFirst boot notes:\n"
log "  - Have HDMI/serial console ready for debugging\n"
log "  - If kernel panic occurs, check F2FS module availability\n"
log "  - Run 'lsmod | grep f2fs' after boot to verify module loaded\n"
