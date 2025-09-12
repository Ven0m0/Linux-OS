#!/usr/bin/env bash
#
# Optimized Raspbian F2FS installer
#
# This script copies a Raspbian image to a target device or image file,
# converting the root filesystem to F2FS for improved performance and
# wear-leveling on flash media.
#
# Usage:
#   $(basename "$0") [options] [source.img|source.zip] [/dev/target|target.img]
#
# Options:
#   -s SIZE_MB  : FAT32 partition size in MiB (minimum 1024). Default 1024.
#   -I          : Interactively select source image with fzf.
#   -D          : Interactively select target device with fzf.
#   -h          : Show this help.
#
# Examples:
#   $(basename "$0") -s 2048 raspbian.img /dev/sdb
#   $(basename "$0") -I -D
#

set -euo pipefail
shopt -s nullglob globstar

# Ensure root access and proper shell/pathing
[[ "$(id -u)" -eq 0 ]] || { echo "Error: This script must be run as root." >&2; exit 1; }
export LC_ALL=C LANG=C SHELL="${BASH:-$(command -v bash)}"
cd -P -- "$(dirname "${BASH_SOURCE[0]}")" || exit 1
sync
sudo -v

# --- Configuration & Defaults ---
declare -A CONFIG=(
  [FAT_MB]=1024
  [SELECT_IMAGE]=0
  [SELECT_DEVICE]=0
  [SCRIPT_VER]="v3.0.0"
  [CMDNAME]="$(basename "$0")"
  [SOURCE_IMG]=""
  [TARGET_DEV]=""
  [TARGET_IMG]=""
)

declare -A MOUNTS=(
  [SOURCE_BOOT]="/mnt/source_boot"
  [SOURCE_ROOT]="/mnt/source_root"
  [TARGET_BOOT]="/mnt/target_boot"
  [TARGET_ROOT]="/mnt/target_root"
)

declare -A LOOPS=(
  [SOURCE_DEV]=""
  [TARGET_DEV]=""
)

declare -A UUIDS=(
  [BOOT]=""
  [ROOT]=""
)

# --- Functions ---

# Print usage information
usage() {
  cat <<EOF
Usage: ${CONFIG[CMDNAME]} [options] [source.img|source.zip] [ /dev/target | target.img ]
Options:
  -s SIZE_MB  : FAT32 partition size in MiB (minimum 1024). Default 1024.
  -I          : Interactively select source image with fzf
  -D          : Interactively select target device with fzf
  -h          : this help
Examples:
  ${CONFIG[CMDNAME]} -s 2048 raspbian.img /dev/sdb
  ${CONFIG[CMDNAME]} -I -D
EOF
}

# Cleanup function to be run on exit, error, or interrupt
cleanup() {
  local exit_code=$?
  printf "\n${CONFIG[CMDNAME]}: Performing cleanup...\n"

  # Umount all
  for m in "${MOUNTS[@]}"; do
    mountpoint -q "$m" && umount "$m" 2>/dev/null || true
  done

  # Delete loop devices
  for l in "${LOOPS[@]}"; do
    [[ -n "$l" ]] && losetup -d "$l" 2>/dev/null || true
  done

  # Remove mount directories
  for m in "${MOUNTS[@]}"; do
    [[ -d "$m" ]] && rm -rf "$m"
  done
  
  if [[ $exit_code -ne 0 ]]; then
    printf "${CONFIG[CMDNAME]}: Script failed with exit code %s.\n" "$exit_code"
  else
    printf "${CONFIG[CMDNAME]}: Cleanup complete.\n"
  fi
}
trap cleanup EXIT

# Interactive source image selection with fzf
pick_image() {
  local files
  IFS=$'\n' read -r -d '' -a files < <(fd -t f --search-path . --max-depth 3 -e img -e zip 2>/dev/null)
  [[ ${#files[@]} -eq 0 ]] && { echo "No .img or .zip files found." >&2; return 1; }
  printf '%s\n' "${files[@]}" | fzf --height=40% --border --preview='bat --style=full --color=always --plain {}' --prompt='Select image> '
}

# Interactive target device selection with fzf using lsblk JSON output
pick_device() {
  local devices
  devices="$(lsblk --json -dpno NAME,MODEL,SIZE,RM,ROTA 2>/dev/null)"
  
  jq -r '.blockdevices[] | select(.rm == true) | .name' <<<"$devices" | fzf --height=40% --border --preview='lsblk -f -no NAME,MODEL,SIZE,RM,ROTA {} 2>/dev/null' --prompt='Select target device> '
}

# --- Main Script Logic ---

# Parse command line options
while getopts "s:IDh" opt; do
  case "$opt" in
    s) CONFIG[FAT_MB]=$OPTARG;;
    I) CONFIG[SELECT_IMAGE]=1;;
    D) CONFIG[SELECT_DEVICE]=1;;
    h) usage; exit 0;;
    *) usage; exit 1;;
  esac
done
shift $((OPTIND-1))

# Enforce minimum FAT size
[[ ${CONFIG[FAT_MB]} -lt 1024 ]] && CONFIG[FAT_MB]=1024

# Resolve source
if [[ ${CONFIG[SELECT_IMAGE]} -eq 1 ]]; then
  CONFIG[SOURCE_IMG]="$(pick_image)" || exit 1
elif [[ $# -ge 1 ]]; then
  CONFIG[SOURCE_IMG]="$1"
  shift
else
  echo "No source provided. Use -I or pass as first argument." >&2
  usage; exit 1
fi

# Resolve target
if [[ ${CONFIG[SELECT_DEVICE]} -eq 1 ]]; then
  CONFIG[TARGET_DEV]="$(pick_device)" || exit 1
elif [[ $# -ge 1 ]]; then
  local targetarg="$1"
  if [[ -b "$targetarg" ]]; then
    CONFIG[TARGET_DEV]="$targetarg"
  else
    CONFIG[TARGET_IMG]="$targetarg"
  fi
  shift
else
  echo "No target provided. Use -D or pass as second argument." >&2
  usage; exit 1
fi

# Handle zipped source image
if [[ "${CONFIG[SOURCE_IMG]##*.}" == "zip" ]]; then
  local imgsrc="${CONFIG[SOURCE_IMG]%.*}.img"
  [[ -r "$imgsrc" ]] || {
    printf "${CONFIG[CMDNAME]}: Unzipping %s to %s...\n" "${CONFIG[SOURCE_IMG]}" "$imgsrc"
    unzip -p "${CONFIG[SOURCE_IMG]}" > "$imgsrc"
  }
  CONFIG[SOURCE_IMG]="$imgsrc"
elif [[ "${CONFIG[SOURCE_IMG]##*.}" != "img" ]]; then
  echo "Source must be .img or .zip." >&2
  exit 1
fi

# Verify and handle target
if [[ -n "${CONFIG[TARGET_DEV]}" ]]; then
  printf "********** THIS DEVICE WILL BE WIPED **********\n"
  parted -s "${CONFIG[TARGET_DEV]}" print || true
  read -rp "********** Are you sure? (yes) **********" ans
  [[ "$ans" == "yes" ]] || exit 1
elif [[ -n "${CONFIG[TARGET_IMG]}" ]]; then
  local target_img_size_mb
  target_img_size_mb="$(du -BM "${CONFIG[SOURCE_IMG]}" | awk '{print $1}' | sed 's/M//g')"
  target_img_size_mb=$((target_img_size_mb + 200))
  printf "${CONFIG[CMDNAME]}: Creating blank disk image %s of size %sMiB.\n" "${CONFIG[TARGET_IMG]}" "$target_img_size_mb"
  truncate -s "${target_img_size_mb}M" "${CONFIG[TARGET_IMG]}"
fi

# Create mount points
for m in "${MOUNTS[@]}"; do
  mkdir -p "$m"
done

# Set up loop devices
printf "${CONFIG[CMDNAME]}: Attaching source image %s...\n" "${CONFIG[SOURCE_IMG]}"
LOOPS[SOURCE_DEV]="$(losetup --show -f -P "${CONFIG[SOURCE_IMG]}")"

if [[ -n "${CONFIG[TARGET_IMG]}" ]]; then
  printf "${CONFIG[CMDNAME]}: Attaching target image %s...\n" "${CONFIG[TARGET_IMG]}"
  LOOPS[TARGET_DEV]="$(losetup --show -f -P "${CONFIG[TARGET_IMG]}")"
fi

# Set target device variable
if [[ -n "${LOOPS[TARGET_DEV]}" ]]; then
  CONFIG[TARGET_DEV]="${LOOPS[TARGET_DEV]}"
fi

# Determine partition suffixes (e.g., p1, 1)
# This is a bit of a hack, but works with most modern `losetup -P`
case "${CONFIG[TARGET_DEV]}" in
  *mmcblk*) 
    local part_suffix=("p1" "p2") 
    ;;
  *sd*) 
    local part_suffix=("1" "2") 
    ;;
  *) 
    # Fallback to a common pattern. `losetup -P` handles this nicely.
    local part_suffix=("p1" "p2") 
    ;;
esac

# Mount source partitions
printf "${CONFIG[CMDNAME]}: Mounting source partitions...\n"
mount -o ro "${LOOPS[SOURCE_DEV]}${part_suffix[0]}" "${MOUNTS[SOURCE_BOOT]}"
mount -o ro "${LOOPS[SOURCE_DEV]}${part_suffix[1]}" "${MOUNTS[SOURCE_ROOT]}"

# Wipe and partition the target
printf "${CONFIG[CMDNAME]}: Wiping %s and creating partitions...\n" "${CONFIG[TARGET_DEV]}"
wipefs -aq "${CONFIG[TARGET_DEV]}"
parted -s "${CONFIG[TARGET_DEV]}" mklabel msdos \
  mkpart primary fat32 8192s "${CONFIG[FAT_MB]}MiB" \
  mkpart primary ext2 "${CONFIG[FAT_MB]}MiB" 100%
partprobe "${CONFIG[TARGET_DEV]}"

# Get partition UUIDs
UUIDS[BOOT]="$(blkid -o value -s PARTUUID "${CONFIG[TARGET_DEV]}${part_suffix[0]}")"
UUIDS[ROOT]="$(blkid -o value -s PARTUUID "${CONFIG[TARGET_DEV]}${part_suffix[1]}")"

# Format and copy boot partition
printf "${CONFIG[CMDNAME]}: Formatting boot partition and copying files...\n"
mkfs.fat -n boot "${CONFIG[TARGET_DEV]}${part_suffix[0]}"
mount "${CONFIG[TARGET_DEV]}${part_suffix[0]}" "${MOUNTS[TARGET_BOOT]}"
rsync -a -v --progress "${MOUNTS[SOURCE_BOOT]}/" "${MOUNTS[TARGET_BOOT]}/"

# Update cmdline.txt
printf "${CONFIG[CMDNAME]}: Updating cmdline.txt with new PARTUUID and rootfstype...\n"
sed -i \
  -e 's/rootfstype=[^ ]*/rootfstype=f2fs/g' \
  -e "s/root=[^ ]*/root=PARTUUID=${UUIDS[ROOT]}/g" \
  -e 's| init=/usr/lib/raspi-config/init_resize.sh||' \
  "${MOUNTS[TARGET_BOOT]}/cmdline.txt"

sync

# Format and copy root partition
printf "${CONFIG[CMDNAME]}: Formatting root partition and copying files...\n"
mkfs.f2fs -o 20 -O extra_attr,inode_checksum,sb_checksum,compression -l root "${CONFIG[TARGET_DEV]}${part_suffix[1]}"
mount "${CONFIG[TARGET_DEV]}${part_suffix[1]}" "${MOUNTS[TARGET_ROOT]}"
rsync -a -v --progress "${MOUNTS[SOURCE_ROOT]}/" "${MOUNTS[TARGET_ROOT]}/"

# Create new fstab
printf "${CONFIG[CMDNAME]}: Generating new fstab...\n"
cat > "${MOUNTS[TARGET_ROOT]}/etc/fstab" << EOF
proc              /proc    proc    defaults              0  0
PARTUUID=${UUIDS[BOOT]}  /boot    vfat    defaults              0  2
PARTUUID=${UUIDS[ROOT]}  /        f2fs    defaults,noatime,discard  0  1
EOF

# Chroot and install f2fs-tools
printf "${CONFIG[CMDNAME]}: Building chroot environment and installing f2fs-tools...\n"
for i in dev proc sys dev/pts; do
  mount --bind "/$i" "${MOUNTS[TARGET_ROOT]}/$i"
done
mount --bind "${MOUNTS[TARGET_BOOT]}" "${MOUNTS[TARGET_ROOT]}/boot"

chroot "${MOUNTS[TARGET_ROOT]}" /bin/bash -c "
  set -euo pipefail
  export TERM=$TERM

  printf '${CONFIG[CMDNAME]}: Stopping automatic ext4 filesystem expansion.\\n'
  update-rc.d resize2fs_once remove || true
  rm -f /etc/init.d/resize2fs_once

  printf '${CONFIG[CMDNAME]}: Installing f2fs-tools.\\n'
  apt-get -qq update && apt-get -qq install -y f2fs-tools || true
  apt-get -qq clean
"

printf "${CONFIG[CMDNAME]}: Tearing down chroot environment...\n"
for i in boot dev/pts sys proc dev; do
  umount "${MOUNTS[TARGET_ROOT]}/$i" || true
done

# Final sync and summary
sync
printf "\n${CONFIG[CMDNAME]}: Installation complete!\n"
df -hT "${CONFIG[TARGET_DEV]}${part_suffix[0]}" "${CONFIG[TARGET_DEV]}${part_suffix[1]}" || true
