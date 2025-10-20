#!/usr/bin/env bash
# raspi-flash.sh - Flash Raspberry Pi images to SD card
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob
export LC_ALL=C LANG=C

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }
info() { log "INFO: $*"; }
error() {
  log "ERROR: $*" >&2
  exit 1
}

main() {
  local src=${1:-} tgt=${2:-}

  [[ $EUID -ne 0 ]] && error "Run as root: sudo $0 <image> <device>"
  [[ -z $src ]] && error "Usage: $0 <image.img[.xz]> </dev/sdX>"
  [[ -z $tgt || ! -b $tgt ]] && error "Target must be block device: $tgt"

  command -v pv &>/dev/null || {
    info "Install pv for progress: pacman -S pv"
    sleep 2
  }

  info "Flashing $src → $tgt"
  read -rp "Type YES to DESTROY $tgt: " confirm
  [[ $confirm == YES ]] || error "Aborted"

  umount "${tgt}"* &>/dev/null || :

  if [[ $src == *.xz ]]; then
    info "Decompressing and flashing..."
    xz -dc "$src" | pv -pterb | dd of="$tgt" bs=4M conv=fsync status=progress
  else
    info "Flashing..."
    pv -pterb "$src" | dd of="$tgt" bs=4M conv=fsync status=progress
  fi

  sync
  info "Done! Remove card, insert into Pi, boot once, then run raspi-migrate-f2fs.sh"
}

main "$@"
