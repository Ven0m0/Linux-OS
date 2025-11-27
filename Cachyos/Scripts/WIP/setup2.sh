#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive

# ============================================================================
# CachyOS System Configuration
# Combines: lockout limits, sudo retries, NVIDIA setup, printer config, wireless regdom
# ============================================================================

configure_auth_limits() {
  # Increase login lockout to 10 attempts, 2min timeout
  sudo sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' /etc/pam.d/system-auth
  sudo sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' /etc/pam.d/system-auth
  
  # Increase sudo password retries to 10
  echo "Defaults passwd_tries=10" | sudo tee /etc/sudoers.d/passwd-tries >/dev/null
  sudo chmod 440 /etc/sudoers.d/passwd-tries
}

setup_nvidia() {
  lspci | grep -qi 'nvidia' || return 0
  
  # Select driver: open-source for RTX 20xx+ / GTX 16xx+
  local driver="nvidia-dkms"
  lspci | grep -i 'nvidia' | grep -qE "RTX [2-9][0-9]|GTX 16" && driver="nvidia-open-dkms"
  
  # Detect kernel headers
  local headers="linux-headers"
  pacman -Q linux-zen &>/dev/null && headers="linux-zen-headers"
  pacman -Q linux-lts &>/dev/null && headers="linux-lts-headers"
  pacman -Q linux-hardened &>/dev/null && headers="linux-hardened-headers"
  
  sudo pacman -Syu --noconfirm
  sudo pacman -S --needed --noconfirm "$headers" "$driver" nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver qt5-wayland qt6-wayland
  
  # Early KMS
  echo "options nvidia_drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf >/dev/null
  
  # mkinitcpio: remove old nvidia modules, add fresh
  local conf=/etc/mkinitcpio.conf
  sudo cp "$conf" "${conf}.backup"
  sudo sed -i -E 's/ nvidia(_drm|_uvm|_modeset)?//g' "$conf"
  sudo sed -i -E 's/^(MODULES=\()/\1nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$conf"
  sudo sed -i -E 's/  +/ /g' "$conf"
  sudo mkinitcpio -P
  
  # Hyprland env vars
  [[ -f "$HOME/.config/hypr/hyprland.conf" ]] && cat >>"$HOME/.config/hypr/hyprland.conf" <<'EOF'

# NVIDIA environment variables
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
}

setup_printers() {
  sudo systemctl enable --now cups.service
  
  # Disable systemd-resolved mDNS; use avahi
  sudo mkdir -p /etc/systemd/resolved.conf.d
  echo -e "[Resolve]\nMulticastDNS=no" | sudo tee /etc/systemd/resolved.conf.d/10-disable-multicast.conf >/dev/null
  sudo systemctl enable --now avahi-daemon.service
  
  # Enable mDNS in nsswitch
  sudo sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve files myhostname dns/' /etc/nsswitch.conf
  
  # Auto-add remote printers
  grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf 2>/dev/null || echo 'CreateRemotePrinters Yes' | sudo tee -a /etc/cups/cups-browsed.conf >/dev/null
  sudo systemctl enable --now cups-browsed.service
}

set_wireless_regdom() {
  [[ -f /etc/conf.d/wireless-regdom ]] && . /etc/conf.d/wireless-regdom
  [[ -n "${WIRELESS_REGDOM:-}" ]] && return 0
  
  [[ -e /etc/localtime ]] || return 0
  local tz country
  tz=$(readlink -f /etc/localtime)
  tz=${tz#/usr/share/zoneinfo/}
  country="${tz%%/*}"
  
  # Extract country from zone.tab if not 2-letter code
  [[ ! "$country" =~ ^[A-Z]{2}$ && -f /usr/share/zoneinfo/zone.tab ]] && country=$(awk -v tz="$tz" '$3 == tz {print $1; exit}' /usr/share/zoneinfo/zone.tab)
  
  [[ "$country" =~ ^[A-Z]{2}$ ]] || return 0
  echo "WIRELESS_REGDOM=\"$country\"" | sudo tee -a /etc/conf.d/wireless-regdom >/dev/null
  command -v iw &>/dev/null && sudo iw reg set "$country" || :
}

# ============================================================================
# Main
# ============================================================================
configure_auth_limits
setup_nvidia
setup_printers
set_wireless_regdom

printf '\nConfiguration complete.\n'
