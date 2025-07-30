#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
if [[ $EUID -ne 0 ]]; then
  echo "Ensuring root perms...";  sudo -v || { echo "Sudo failed. Exiting."; exit 1; }
fi
# f2fs-fstab-tune.sh
# Interactive F2FS fstab entry updater for root filesystem
# Usage: sudo ./f2fs-fstab-tune.sh

# Detect root device and ensure it's F2FS
device=$(findmnt -n -o SOURCE /)
fs_type=$(findmnt -n -o FSTYPE "$device")
fs_type=$(findmnt -n -o FSTYPE ${device:-/})
if [[ "$fs_type" != "f2fs" ]]; then
  echo "Error: Root fs isnt F2FS (detected type: $fs_type). Exiting."; exit 1
fi
# Get UUID
UUID=$(sudo blkid -s UUID -o value "$device")
# Desktop vs Server presets
desktop_opts="defaults,noatime,mode=adaptive,memory=normal,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=on"
server_opts="defaults,noatime,nodiratime,mode=adaptive,memory=high,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=sync,flush_merge,nobarrier"

# Interactive selection
echo "Select tuning profile for F2FS root (/):"
select profile in "Desktop (balanced)" "Server (performance)" "Custom"; do
  case $profile in
    "Desktop (balanced)") opts="$desktop_opts"; break;;
    "Server (performance)") opts="$server_opts"; break;;
    "Custom") read -rp "Enter custom mount options (comma-separated): " opts; break;;
    *) echo "Invalid choice.";;
  esac
done

# Confirm chosen options
echo -e "\nSelected options:\n  $opts\n"
read -rp "Proceed to update /etc/fstab with these options? [Y/n] " confirm
confirm=${confirm:-Y}
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted by user."; exit 0
fi

# Backup fstab
backup="/etc/fstab.bak.$(date +%F_%H%M%S)"
sudo cp /etc/fstab "$backup"
echo -e "\nBackup saved to $backup\m"
# Remove existing root entry by UUID
sudo sed -i "\|^UUID=$UUID[[:space:]]\+/[[:space:]]\+f2fs|d" /etc/fstab
# Append new entry
printf "UUID=%s\t/\tf2fs\t%s\t0\t1\n" "$UUID" "$opts" | sudo tee -a /etc/fstab > /dev/null

echo "/etc/fstab updated."

echo "To apply immediately, run:"
echo "  sudo mount -o remount,$opts /"
exit 0
