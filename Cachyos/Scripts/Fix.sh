#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C LANG=C.UTF-8
# https://github.com/ekahPruthvi/cynageOS
# https://wiki.cachyos.org/cachyos_basic/faq/
SHELL="${BASH:-$(command -vp bash)}"
export HOME="/home/${SUDO_USER:-$USER}"
sudo -v
sync
builtin cd -P -- "${BASH_SOURCE[0]%/*}"
cd "$(printf '%s\n' "${BASH_SOURCE[0]%/*}")"
WORKDIR="$(builtin cd -Pe -- "${BASH_SOURCE[0]%/*}" && builtin printf '%s\n' "${PWD:-$(pwd -P)}")"
builtin cd -- "$WORKDIR" || exit 1
cd -- "$(builtin cd -Pe -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && builtin printf '%s\n' "${PWD:-$(pwd)}")"

builtin cd -Pe -- "$(command dirname -- "${BASH_SOURCE[0]:-}" && builtin printf '%s\n' "${PWD:-$(pwd -P)}")" || exit 1

WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1

update() {
  [[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root -- /var/lib/pacman/db.lck >/dev/null
  sudo pacman -Syu --noconfirm
  command -v paru &>/dev/null && {
    paru -Sua --noconfirm
    paru -Syu --noconfirm
  }
  command -v yay &>/dev/null && {
    yay -Sua --noconfirm
    yay -Syu --noconfirm
  }
}

mirrorfix() {
  echo "Fix mirrors"
  command -v cachyos-rate-mirrors &>/dev/null && sudo cachyos-rate-mirrors
}

cache() {
  sudo rm -r /var/cache/pacman/pkg/*
  sudo pacman -Sccq --noconfirm
  command -v paru &>/dev/null && paru -Sccq --noconfirm
  command -v yay &>/dev/null && yay -Sccq --noconfirm
}

# SSH fix
sudo chmod -R 744 ~/.ssh
sudo chmod -R 744 ~/.gnupg

# Fix keyrings
sudo rm -rf /etc/pacman.d/gnupg/ # Force-remove the old keyrings
sudo pacman -Sy archlinux-keyring --noconfirm || sudo pacman -Sy archlinux-keyring --noconfirm
sudo pacman-key --refresh-keys
sudo pacman-key --init                                                        # Initialize the keyring
sudo pacman-key --populate                                                    # Populate the keyring
sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com # Manually import the CachyOS key
sudo pacman-key --lsign-key F3B607488DB35A47                                  # Manually sign the key
sudo pacman-key --lsign cachyos
sudo rm -R /var/lib/pacman/sync # Remove the synced databases to force a fresh download

echo "Fixing Fakeroot error"
sudo pacman -Sy --needed base-devel

echo "Fixing wlogout pgp keyring error"
# Prefer aria2 -> curl -> wget2 -> wget for downloads
if command -v aria2c &>/dev/null; then
  aria2c -q -d /tmp -o wlogout.asc https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F && gpg --import /tmp/wlogout.asc && rm /tmp/wlogout.asc
elif command -v curl &>/dev/null; then
  curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
elif command -v wget2 &>/dev/null; then
  wget2 -qO- https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
else
  wget -qO- https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -
fi

sudo pacman -Syyu --noconfirm
