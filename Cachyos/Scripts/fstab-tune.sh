#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Initialize privilege tool
PRIV_CMD=$(init_priv)

# f2fs-fstab-tune.sh
# Interactive F2FS fstab entry updater for root filesystem
# Usage: sudo ./f2fs-fstab-tune.sh

# Detect root device and ensure it's F2FS
device=$(findmnt -n -o SOURCE /)
fs_type=$(findmnt -n -o FSTYPE "${device:-/}")
[[ "$fs_type" != "f2fs" ]] && die "Root fs isn't F2FS (detected type: ${fs_type}). Exiting."

# Get UUID
UUID=$(run_priv blkid -s UUID -o value "$device")
# Desktop vs Server presets
desktop_opts="defaults,noatime,mode=adaptive,memory=normal,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=on"
server_opts="defaults,noatime,nodiratime,mode=adaptive,memory=high,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=sync,flush_merge,nobarrier"

# Interactive selection
echo "Select tuning profile for F2FS root (/):"
select profile in "Desktop (balanced)" "Server (performance)" "Custom"; do
  case "$profile" in
    "Desktop (balanced)") opts="$desktop_opts"; break;;
    "Server (performance)") opts="$server_opts"; break;;
    "Custom") read -rp "Enter custom mount options (comma-separated): " opts; break;;
    *) echo "Invalid choice.";;
  esac
done

# Confirm chosen options
printf '%b\n' "Selected options:\n${opts}"
read -rp "Proceed to update /etc/fstab with these options? [Y/n] " confirm
[[ ! "${confirm:-Y}" =~ ^[Yy]$ ]] && { echo "Aborted by user."; exit 0; }

# Backup fstab
backup="/etc/fstab.bak.$(printf '%(%F-%H-%M)T' -1)"
run_priv cp -f -- /etc/fstab "$backup"
printf '%s\n' "Backup saved to ${backup}"
# Remove existing root entry by UUID
run_priv sed -i "\|^UUID=${UUID}[[:space:]]\+/[[:space:]]\+f2fs|d" /etc/fstab
# Append new entry
printf "UUID=%s\t/\tf2fs\t%s\t0\t1\n" "$UUID" "$opts" | run_priv tee -a /etc/fstab > /dev/null
printf '%s\n' "/etc/fstab updated."
printf '%s\n' "To apply immediately, run:"
printf '%s\n' " sudo mount -o remount,${opts} /"
exit 0
