#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Helpers
msg(){ printf '%b%s%b\n' "$GRN" "$*" "$DEF"; }
warn(){ printf '%b%s%b\n' "$YLW" "$*" "$DEF" >&2; }
die(){ printf '%b%s%b\n' "$RED" "$*" "$DEF" >&2; exit "${2:-1}"; }
has(){ command -v "$1" &>/dev/null; }
# Profiles
OPT_DESKTOP="defaults,noatime,mode=adaptive,memory=normal,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=on"
OPT_SERVER="defaults,noatime,nodiratime,mode=adaptive,memory=high,compress_algorithm=zstd,compress_chksum,inline_xattr,inline_data,checkpoint_merge,background_gc=sync,flush_merge,nobarrier"
edit_at_line(){ sudo "${EDITOR:-vim}" +"$1" "$2"; }
fstab_pick(){
  local fstab="$1"; shift
  mapfile -t NL < <(nl -ba -w6 -s$'\t' "$fstab")
  # gum
  if has gum; then
    sel=$(printf '%s\n' "${NL[@]}" | gum choose --height=14) || sel=
    [[ -n "$sel" ]] && printf '%s\n' "${sel%%$'\t'*}" && return 0
  fi
  # fzf
  if has fzf; then
    sel=$(printf '%s\n' "${NL[@]}" \
      | fzf --ansi --reverse --prompt="fstab> " \
            --preview='ln=$(echo {}|cut -f1); sed -n "$((ln-3)),$((ln+3))p" '"$fstab" \
            --preview-window=up:wrap:3) || sel=
    [[ -n "$sel" ]] && printf '%s\n' "${sel%%$'\t'*}" && return 0
  fi
  # whiptail
  if has whiptail; then
    mapfile -t act < <(grep -n '^[[:space:]]*[^#[:space:]]' "$fstab" || :)
    if [[ ${#act[@]} -gt 0 ]]; then
      opts=()
      for l in "${act[@]}"; do
        ln="${l%%:*}"; txt="${l#*:}"
        opts+=("$ln" "${txt:0:80}")
      done
      choice=$(whiptail --title "fstab entries" --menu "Select entry" 20 76 12 "${opts[@]}" 3>&1 1>&2 2>&3) || choice=
      [[ -n "$choice" ]] && printf '%s\n' "$choice" && return 0
    fi
  fi
  # fallback = editor
  edit_at_line 1 "$fstab"; return 1
}

main() {
  [[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"
  local fstab="/etc/fstab"
  msg "Detecting filesystem..."
  local root_src root_type root_uuid line
  root_src=$(findmnt -n -o SOURCE /)
  root_type=$(findmnt -n -o FSTYPE /)
  [[ "$root_type" == "f2fs" ]] || die "Root filesystem is not F2FS (Detected: $root_type)."
  root_uuid=$(blkid -s UUID -o value "$root_src") || die "UUID lookup failed"
  printf "  Device: %s\n  UUID:   %s\n  Type:   %s\n\n" "$root_src" "$root_uuid" "$root_type"
  # 0. Allow user to visually inspect fstab first
  msg "Inspect fstab? (optional)"
  read -rp "Open an entry in an editor first? [y/N] " ans
  if [[ "${ans,,}" =~ ^y ]]; then
    line=$(fstab_pick "$fstab") || :
    [[ -n "${line:-}" ]] && edit_at_line "$line" "$fstab"
  fi
  # 1. Profile selection
  echo "${BLD}Select tuning profile:${DEF}"
  local opts=""
  select profile in "Desktop (Balanced/Safe)" "Server (Performance/Risk)" "Custom"; do
    case "$profile" in
      "Desktop"*) opts="$OPT_DESKTOP"; break ;;
      "Server"*)  opts="$OPT_SERVER"; break ;;
      "Custom")   read -rp "Enter mount options: " opts; break ;;
      *) warn "Invalid selection";;
    esac
  done
  [[ -z "$opts" ]] && die "No options selected"
  printf "\n%bSelected Options:%b\n%s\n\n" "$CYN" "$DEF" "$opts"
  read -rp "Apply these changes to /etc/fstab? [y/N] " ans
  [[ "${ans,,}" =~ ^y ]] || die "Aborted by user" 0
  # 2. Backup & Apply
  local backup="${fstab}.bak.$(date +%Y%m%d_%H%M%S)"
  msg "Backing up fstab to $backup..."
  cp -f "$fstab" "$backup"
  msg "Updating fstab..."
  sed -i "\|^UUID=${root_uuid}[[:space:]]\+/[[:space:]]\+f2fs|d" "$fstab"
  printf "UUID=%-36s /    f2fs    %s 0 1\n" "$root_uuid" "$opts" >> "$fstab"
  msg "Done."
  warn "Reboot or run 'mount -o remount /' to apply."
}
main "$@"
