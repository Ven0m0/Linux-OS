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
  [[ -n "${MNT_OLD:-}" ]] && mountpoint -q "$MNT_OLD" && umount -R "$MNT_OLD"
  [[ -n "${MNT_NEW:-}" ]] && mountpoint -q "$MNT_NEW" && umount -R "$MNT_NEW"
  [[ -n "${MNT_BOOT:-}" ]] && mountpoint -q "$MNT_BOOT" && umount -R "$MNT_BOOT"
  [[ -n "${LOOP_OLD:-}" ]] && losetup -d "$LOOP_OLD" &>/dev/null
  [[ -n "${LOOP_NEW:-}" ]] && losetup -d "$LOOP_NEW" &>/dev/null
  [[ -n "${WORKDIR:-}" && -d "${WORKDIR:-}" ]] && rm -rf -- "$WORKDIR"
}
trap cleanup EXIT

usage(){
  cat <<'EOF'
Usage:
  dietpi-f2fs-image.sh --image-url URL [--out OUT.img] [--root-label LABEL] [--root-opts "opts"]

Example:
  ./dietpi-f2fs-image.sh \
    --image-url "https://dietpi.com/downloads/images/DietPi_RPi-ARMv8-Bookworm.img.xz" \
    --out DietPi_RPi4_f2fs.img

Notes:
- /boot stays vfat.
- Root partition becomes f2fs.
- You should validate f2fs support on your kernel/boot path.
EOF
}

IMAGE_URL=""
OUT_IMG=""
ROOT_LABEL="dietpi-root"
ROOT_OPTS="compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime"
# ROOT_OPTS is conservative-ish; tune later.

while (($#)); do
  case "$1" in
    --image-url) IMAGE_URL="${2:-}"; shift 2;;
    --out) OUT_IMG="${2:-}"; shift 2;;
    --root-label) ROOT_LABEL="${2:-}"; shift 2;;
    --root-opts) ROOT_OPTS="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

[[ -n "$IMAGE_URL" ]] || { usage; die "Need --image-url"; }

need git
need curl
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

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

fname_from_url(){ local u="$1"; printf '%s\n' "${u##*/}"; }
SRC_ARCHIVE="$(fname_from_url "$IMAGE_URL")"
log "Downloading: $IMAGE_URL\n"
curl -fL --retry 5 --retry-delay 2 -o "$SRC_ARCHIVE" "$IMAGE_URL"

IMG_SRC=""
case "$SRC_ARCHIVE" in
  *.img) IMG_SRC="$SRC_ARCHIVE";;
  *.img.xz)
    need xz
    log "Decompressing xz...\n"
    xz -dk "$SRC_ARCHIVE"
    IMG_SRC="${SRC_ARCHIVE%.xz}"
    ;;
  *.img.gz)
    need gzip
    log "Decompressing gz...\n"
    gzip -dk "$SRC_ARCHIVE"
    IMG_SRC="${SRC_ARCHIVE%.gz}"
    ;;
  *)
    die "Unsupported image type: $SRC_ARCHIVE (expect .img, .img.xz, .img.gz)"
    ;;
esac

[[ -f "$IMG_SRC" ]] || die "Source image not found after decompress: $IMG_SRC"

# Output image path
if [[ -z "$OUT_IMG" ]]; then
  OUT_IMG="$(pwd)/DietPi_f2fs.img"
else
  OUT_IMG="$(readlink -f -- "$OUT_IMG")"
fi

log "Copying image to: $OUT_IMG\n"
cp -f -- "$IMG_SRC" "$OUT_IMG"

# Attach loop for the working image
LOOP_OLD="$(losetup --find --show --partscan "$OUT_IMG")"
log "Loop device: $LOOP_OLD\n"

# Detect partitions: assume p1=boot, p2=root (DietPi typical)
BOOT_DEV="${LOOP_OLD}p1"
ROOT_DEV="${LOOP_OLD}p2"
[[ -b "$BOOT_DEV" && -b "$ROOT_DEV" ]] || die "Expected partitions not found: $BOOT_DEV and $ROOT_DEV"

# Sanity: root must be ext4 currently
root_fstype="$(blkid -o value -s TYPE "$ROOT_DEV" || true)"
[[ "$root_fstype" == "ext4" ]] || die "Expected ext4 rootfs on $ROOT_DEV, got: ${root_fstype:-unknown}"

# Reduce ext4 to make room for recreation? We will recreate partition in-place:
# Steps:
# - fsck ext4
# - (optional) shrink ext4 to minimum? Not needed if we keep same start/end and just reformat.
# We'll keep same geometry: record start/end sectors then recreate partition with same boundaries, then mkfs.f2fs.

read_part_geom(){
  local dev="$1" partnum="$2"
  # Output: start end (sectors)
  # parted -m: unit s ensures sectors
  parted -m -s "$dev" unit s print | awk -F: -v p="$partnum" '$1==p {gsub(/s/,"",$2); gsub(/s/,"",$3); print $2, $3}'
}

# parted operates on the loop device (disk), not partition node
DISK_DEV="$LOOP_OLD"
geom="$(read_part_geom "$DISK_DEV" 2)"
[[ -n "$geom" ]] || die "Failed to read partition 2 geometry"
read -r ROOT_START ROOT_END <<<"$geom"

log "Root partition geometry (sectors): start=$ROOT_START end=$ROOT_END\n"

log "Running e2fsck/resize2fs preflight...\n"
e2fsck -fy "$ROOT_DEV" >/dev/null
# Ensure ext4 is maximally compact (not strictly needed but reduces rsync time sometimes after boots)
resize2fs -M "$ROOT_DEV" >/dev/null || true

# Mount old root and boot
MNT_OLD="$WORKDIR/mnt_old"
MNT_BOOT="$WORKDIR/mnt_boot"
mkdir -p "$MNT_OLD" "$MNT_BOOT"
mount -o ro "$ROOT_DEV" "$MNT_OLD"
mount "$BOOT_DEV" "$MNT_BOOT"

# Unmount old root so we can delete/recreate partition 2 safely
umount -R "$MNT_OLD"

log "Recreating partition 2 as f2fs...\n"
parted -s "$DISK_DEV" rm 2
parted -s "$DISK_DEV" unit s mkpart primary "$ROOT_START" "$ROOT_END"
partprobe "$DISK_DEV" || true
# loopdev partition nodes can lag; force re-scan
losetup -d "$LOOP_OLD" &>/dev/null
LOOP_NEW="$(losetup --find --show --partscan "$OUT_IMG")"
LOOP_OLD="$LOOP_NEW"
BOOT_DEV="${LOOP_OLD}p1"
ROOT_DEV="${LOOP_OLD}p2"

[[ -b "$ROOT_DEV" ]] || die "Root partition device missing after recreate: $ROOT_DEV"

log "Formatting root as f2fs (label=$ROOT_LABEL)...\n"
mkfs.f2fs -f -l "$ROOT_LABEL" "$ROOT_DEV" >/dev/null

# Mount new root and boot
MNT_NEW="$WORKDIR/mnt_new"
mkdir -p "$MNT_NEW"
mount "$ROOT_DEV" "$MNT_NEW"
mount "$BOOT_DEV" "$MNT_BOOT"

# Re-mount original root (now gone), so we need source from image before we nuked it.
# We already nuked it. So we must copy from a preserved snapshot.
# Fix: Use a second loop attached to the original IMG_SRC as the source.
log "Attaching source image for copy...\n"
LOOP_SRC="$(losetup --find --show --partscan "$IMG_SRC")"
SRC_ROOT="${LOOP_SRC}p2"
SRC_BOOT="${LOOP_SRC}p1"
[[ -b "$SRC_ROOT" ]] || die "Source root partition missing: $SRC_ROOT"
SRC_MNT="$WORKDIR/mnt_src"
mkdir -p "$SRC_MNT"
mount -o ro "$SRC_ROOT" "$SRC_MNT"

log "Copying rootfs to f2fs (rsync)...\n"
# Keep numeric ids; preserve xattrs/acls if possible.
rsync -aHAX --numeric-ids --info=progress2 \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
  "$SRC_MNT"/ "$MNT_NEW"/

umount -R "$SRC_MNT"
losetup -d "$LOOP_SRC" &>/dev/null

# Update /etc/fstab in new root
FSTAB="$MNT_NEW/etc/fstab"
if [[ -f "$FSTAB" ]]; then
  log "Updating fstab...\n"
  # Replace rootfs line to f2fs; keep boot line intact.
  # DietPi fstab varies; do minimal surgery.
  # If it uses UUID= for /, keep it but update fstype.
  # If it uses /dev/mmcblk0p2, keep it but update fstype.
  sed -i \
    -e 's/[[:space:]]\+ext4[[:space:]]\+defaults[[:space:]]/ f2fs defaults /' \
    -e 's/[[:space:]]\+ext4[[:space:]]\+/ f2fs /' \
    "$FSTAB" || true
fi

# Determine new root UUID
ROOT_UUID="$(blkid -o value -s UUID "$ROOT_DEV")"
[[ -n "$ROOT_UUID" ]] || die "Failed to read UUID from new f2fs root"

# Update /boot/cmdline.txt to rootfstype=f2fs and root=UUID=...
CMDLINE="$MNT_BOOT/cmdline.txt"
[[ -f "$CMDLINE" ]] || die "Missing $CMDLINE"

log "Patching cmdline.txt...\n"
cmd="$(<"$CMDLINE")"
# Ensure single line
cmd="${cmd//$'\n'/ }"
# Replace root=... token
cmd="$(sed -E "s/(^|[[:space:]])root=[^[:space:]]+/\1root=UUID=${ROOT_UUID}/" <<<"$cmd")"
# Replace/add rootfstype=f2fs
if grep -qE '(^|[[:space:]])rootfstype=' <<<"$cmd"; then
  cmd="$(sed -E 's/(^|[[:space:]])rootfstype=[^[:space:]]+/\1rootfstype=f2fs/' <<<"$cmd")"
else
  cmd+=" rootfstype=f2fs"
fi
# Add rootflags if not present
if ! grep -qE '(^|[[:space:]])rootflags=' <<<"$cmd"; then
  cmd+=" rootflags=${ROOT_OPTS}"
fi

printf '%s\n' "$cmd" >"$CMDLINE"

# Optional: ensure f2fs tools exist in rootfs (DietPi usually can install on first boot, but root mount must succeed first)
# We'll just verify /sbin/fsck.f2fs existence; if not, warn.
if [[ ! -x "$MNT_NEW/sbin/fsck.f2fs" && ! -x "$MNT_NEW/usr/sbin/fsck.f2fs" ]]; then
  log "WARN: fsck.f2fs not found in image rootfs. Not fatal for boot, but fsck on boot may fail.\n"
fi

sync
umount -R "$MNT_NEW"
umount -R "$MNT_BOOT"

log "Done.\nOutput image: $OUT_IMG\n"
log "Flash it (example): sudo dd if='$OUT_IMG' of=/dev/sdX bs=4M conv=fsync status=progress\n"
