#!/usr/bin/env bash
#──────────── Setup ────────────────────
export LC_ALL=C LANG=C; shopt -s nullglob globstar
WORKDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"
cd $WORKDIR
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; }
hasname(){ local x=$(type -P -- "$1") || return; printf '%s\n' "${x##*/}"; }
xprintf(){ printf "%s\n" "$@"; }
#──────────── Sudo ────────────────────
[[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"; sync
#─────────────────────────────────────────────────────────────
if has nala; then
  "$suexec" nala fetch --auto --sources --fetches 5 --non-free -y -c DE
  "$suexec" nala upgrade
  "$suexec" nala autoremove && "$suexec" nala autopurge
elif has apt-fast; then
  "$suexec" apt-fast update -y && "$suexec" apt-fast upgrade -y
  "$suexec" apt-fast dist-upgrade -y && "$suexec" apt-fast full-upgrade -y
  "$suexec" apt-fast autoremove
else
  "$suexec" apt-get update -y --allow-releaseinfo-change && "$suexec" apt-get upgrade -y
  "$suexec" apt-get dist-upgrade -y && "$suexec" apt full-upgrade -y
fi
# Check's the broken packages and fix them
"$suexec" dpkg --configure -a >/dev/null
if [ $? -ne 0 ]; then
    xprintf "There were issues configuring packages."
else
    xprintf "No broken packages found or fixed successfully."
fi

"$suexec" dietpi-update 1 || "$suexec" /boot/dietpi/dietpi-update 1

has pihole && "$suexec" pihole -up || :

has rpi-eeprom-update && "$suexec" rpi-eeprom-update -a || :
has rpi-update && "$suexec" PRUNE_MODULES=1 rpi-update || :
#"$suexec" JUST_CHECK=1 rpi-update
# "$suexec" PRUNE_MODULES=1 rpi-update
