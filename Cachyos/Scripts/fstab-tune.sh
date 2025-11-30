#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
# Check deps early
has(){ command -v "$1" &>/dev/null; }
for dep in yad findmnt blkid sed cp; do has "$dep" || { printf 'Missing: %s\n' "$dep"; exit 1; }; done
OPT_DESKTOP="defaults,noatime,mode=adaptive,memory=normal,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=on"
OPT_SERVER="defaults,noatime,nodiratime,mode=adaptive,memory=high,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=sync,flush_merge,nobarrier"
# Yad helpers
ymsg(){ yad --info --title="fstab-tune" --text="$1" --width=400 --timeout=7; }
ydie(){ yad --error --title="fstab-tune" --text="$1" --width=400; exit 1; }
yask(){ yad --question --title="fstab-tune" --text="$1" --width=450; }
ypick(){
  local file="$1"
  local entries
  mapfile -t entries < <(awk '($1 ~ "^#" || NF < 4){next} {printf "%d\t%-.55s\n", NR, $0}' "$file")
  [[ ${#entries[@]} -eq 0 ]] && ymsg "No non-comment fstab entries." && return 1
  local pick; pick=$(yad --list --title="fstab entries" --column="Line" --column="Entry" "${entries[@]}" --width=950 --height=300 --center --hide-header --print-all --separator=":" --button=gtk-edit:0 --button=gtk-cancel:1)
  [[ $? -eq 0 && -n "$pick" ]] || return 1
  printf '%s\n' "${pick%%:*}"
}
edit_at_line(){ sudo "${EDITOR:-vim}" +"$1" "$2"; }

# Main
main() {
  [[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"
  local fstab="/etc/fstab" opts optdesc profile backup uuid root_src root_type
  root_src=$(findmnt -n -o SOURCE /)
  root_type=$(findmnt -n -o FSTYPE /)
  [[ "$root_type" == "f2fs" ]] || ydie "Root filesystem is not F2FS (Detected: $root_type)."
  uuid=$(blkid -s UUID -o value "$root_src") || ydie "UUID lookup failed for $root_src"
  ymsg "Device: <b>$root_src</b>\nUUID: <b>$uuid</b>\nType: <b>$root_type</b>"
  # fstab inspect
  yask "Inspect/edit an /etc/fstab entry first?" && {
    local ln; ln=$(ypick "$fstab") || :
    [[ -n "${ln:-}" ]] && edit_at_line "$ln" "$fstab"
  }
  # Profile select
  profile=$(yad --list --title="Select F2FS tuning profile" --width=520 --height=240 --center --radiolist \
    --column=" " --column="Profile" --column="Options" TRUE "Desktop (Balanced/Safe)" "$OPT_DESKTOP" \
    FALSE "Server (Performance/Risk)" "$OPT_SERVER" \
    FALSE "Custom..." "<enter manually>" \
    --separator=":" | cut -d: -f2)
  [[ -z "$profile" ]] && ydie "No profile selected"
  case "$profile" in
    Desktop*)  opts="$OPT_DESKTOP"; optdesc="Desktop profile: balanced/safe defaults." ;;
    Server*)   opts="$OPT_SERVER";  optdesc="Server profile: more aggressive tuning." ;;
    Custom*)   opts=$(yad --entry --title="Custom mount options" --width=600 --text="Enter F2FS mount options:") ;;
    *)         ydie "Invalid profile"
  esac
  [[ -z "$opts" ]] && ydie "No options entered"
  yad --text-info --title="Selected Options" --width=700 --height=130 --center --filename=<(printf "Tuning profile:\n%s\n\n%s" "$profile" "$opts")
  yask "Apply these options (profile: $profile) to root entry in /etc/fstab?\n\n$opts" || exit 0
  # backup
  backup="${fstab}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$fstab" "$backup" || ydie "Failed to backup $fstab"
  ymsg "Backup: $backup"
  # Δ: Remove old, append new root f2fs entry
  sed -i "\|^UUID=${uuid}[[:space:]]\+/[[:space:]]\+f2fs|d" "$fstab"
  printf "UUID=%-36s /    f2fs    %s 0 1\n" "$uuid" "$opts" >> "$fstab"
  yad --info --title="fstab-tune" --text="Updated /etc/fstab\nBackup: $backup" --width=400
  yad --info --title="fstab-tune" --text="Reboot or run:\n<b>mount -o remount /</b>\nto apply." --width=410
}
main "$@"
