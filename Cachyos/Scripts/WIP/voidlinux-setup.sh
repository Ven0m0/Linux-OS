#!/usr/bin/env bash
set -u

# quick post-install: install KDE Plasma on Void Linux (runit)
# usage: run as root

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  printf 'error: run as root\n' >&2
  exit 1
fi

PACKAGES=(
  kde-plasma
  kde-baseapps
  xorg-minimal
  dbus
  elogind
  polkit-elogind
  networkmanager
)

# update repos + install
xbps-install -Syu "${PACKAGES[@]}" &>/dev/null || {
  printf 'xbps-install failed\n' >&2
  exit 1
}

# enable/start required services (runit)
for svc in dbus elogind NetworkManager sddm; do
  [ -d "/etc/sv/$svc" ] && ln -s "/etc/sv/$svc" /var/service/ 2>/dev/null || :
  sv up "$svc" 2>/dev/null || :
done

printf 'kde-plasma install complete. Reboot to start the session.\n'
