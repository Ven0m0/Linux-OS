#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
has(){ command -v "$1" &>/dev/null; }
sync; sudo -v

switch_off_keyboard_backlight(){ echo 0 >/sys/devices/platform/asus-nb-wmi/leds/asus::kbd_backlight/brightness; }
increase_fs_write_cache_timeout(){ echo 1500 >/proc/sys/vm/dirty_writeback_centisecs; }
increase_audio_buffers(){ for i in `find /proc/asound/* -path */prealloc`; do echo 4096 > "$i"; done; }
disable_nmi_watchdog(){ echo 0 >/proc/sys/kernel/nmi_watchdog; }
enable_usb_pm(){
# Powersaving for USB. This disables some USB ports
	for i in `find /sys | grep \/power/level$`; do echo auto > "$i"; done;
	for i in `find /sys | grep \/autosuspend$`; do echo 2 > "$i"; done;
}
silence_audio(){
	amixer set Mic 0% mute
	amixer set Capture 0% mute
	amixer set "Internal Mic" 0% mute
}
disable_usb_polling(){ (udisks --inhibit-all-polling)&; }

# Disable wake on lan for LAN
ethtool -s eth0 wol u || echo not setting wol on eth0
# harddisk
hdparm -B254 /dev/sda

	
