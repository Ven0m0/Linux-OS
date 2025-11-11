#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# https://github.com/ekahPruthvi/cynageOS
# https://wiki.cachyos.org/cachyos_basic/faq/

# Initialize privilege tool
PRIV_CMD=$(init_priv)

update() {
  cleanup_pacman_lock
  run_priv pacman -Syu --noconfirm
  has paru && {
    paru -Sua --noconfirm
    paru -Syu --noconfirm
  }
  has yay && {
    yay -Sua --noconfirm
    yay -Syu --noconfirm
  }
}

mirrorfix() {
  log "Fix mirrors"
  has cachyos-rate-mirrors && run_priv cachyos-rate-mirrors
}

cache() {
  run_priv rm -r /var/cache/pacman/pkg/*
  run_priv pacman -Sccq --noconfirm
  has paru && paru -Sccq --noconfirm
  has yay && yay -Sccq --noconfirm
}

# SSH fix
run_priv chmod -R 744 ~/.ssh
run_priv chmod -R 744 ~/.gnupg

# Fix keyrings
run_priv rm -rf /etc/pacman.d/gnupg/ # Force-remove the old keyrings
run_priv pacman -Sy archlinux-keyring --noconfirm || sudo pacman -Sy archlinux-keyring --noconfirm
run_priv pacman-key --refresh-keys
run_priv pacman-key --init                                                        # Initialize the keyring
run_priv pacman-key --populate                                                    # Populate the keyring
run_priv pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com # Manually import the CachyOS key
run_priv pacman-key --lsign-key F3B607488DB35A47                                  # Manually sign the key
run_priv pacman-key --lsign cachyos
run_priv rm -R /var/lib/pacman/sync # Remove the synced databases to force a fresh download

log "Fixing Fakeroot error"
run_priv pacman -Sy --needed base-devel

log "Fixing wlogout pgp keyring error"
# Prefer aria2 -> curl -> wget2 -> wget for downloads
if has aria2c; then
  aria2c -q -d /tmp -o wlogout.asc https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F && gpg --import /tmp/wlogout.asc && rm /tmp/wlogout.asc
elif has curl; then
  curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
elif has wget2; then
  wget2 -qO- https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
else
  wget -qO- https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
fi

run_priv pacman -Syyu --noconfirm
