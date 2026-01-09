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
  dietpi-trixie-f2fs.sh [--out OUT.img] [--root-label LABEL] [--root-opts "opts"]

Defaults:
  Source URL: https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz
  OUT.img: ./DietPi_RPi234-ARMv8-Trixie_f2fs.img
  LABEL: dietpi-root
  rootflags: compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime

Example:
  sudo ./dietpi-trixie-f2fs.sh --out /tmp/dietpi-f2fs.img
EOF
}

SRC_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"
OUT_IMG="./DietPi_RPi234-ARMv8-Trixie_f2fs.img"
ROOT_LABEL="dietpi-root"
ROOT_OPTS="compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime"

while (($#)); do
  case "$1" in
    --out) OUT_IMG="${2:-}"; shift 2;;
    --root-label) ROOT_LABEL="${2:-}"; shift 2;;
    --root-opts) ROOT_OPTS="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

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

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

src_archive="${SRC_URL##*/}"
log "Downloading: $SRC_URL\n"
curl -fL --retry 5 --retry-delay 2 -o "$src_archive" "$SRC_URL"

log "Decompressing xz...\n"
xz -dk "$src_archive"
SRC_IMG="${src_archive%.xz}"
[[ -f "$SRC_IMG" ]] || die "Decompressed .img not found: $SRC_IMG"

OUT_IMG="$(readlink -f -- "$OUT_IMG")"
log "Copying to output image: $OUT_IMG\n"
cp -f -- "$SRC_IMG" "$OUT_IMG"

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
log "Output image: $OUT_IMG\n"
log "Flash example: sudo dd if='$OUT_IMG' of=/dev/mmcblk0 bs=4M conv=fsync status=progress\n"
log "First boot: have HDMI/serial. If it panics mounting root, your kernel/boot path lacks f2fs-at-boot support.\n"
