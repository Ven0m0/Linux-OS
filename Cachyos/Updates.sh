#!/bin/bash
set -euo pipefail
# shellcheck shell=bash

#–– Helper to test for a binary in $PATH
have() { command -v "$1" >/dev/null 2>&1; }

# 1) Detect and cache privilege executor
if have doas; then
  suexec="doas"
elif have sudo-rs; then
  suexec="sudo-rs"
  sudo-rs -v || true
else
  suexec="/usr/bin/sudo"
  /usr/bin/sudo -v || true
fi

echo "🔄 Updating system..."
# 2) System update
$suexec pacman -Syu --noconfirm
# 3) AUR update
paru -Syu --noconfirm --combinedupgrade --nouseask -q --removemake --cleanafter --skipreview --nokeepsrc
# 4) topgrade (ignore failures)
if have topgrade; then
  topgrade -c --disable=config_update --skip-notify -y \
           --no-retry --disable=uv --disable=pipx --disable=shell || true
fi
# pipx upgrade-all
# 5) Discover updates
if have plasma-discover-update; then
  eval "$(dbus-launch)"
  plasma-discover-update
else
  echo "ℹ️ plasma-discover-update not installed."
fi

# 6) UV tool upgrade (background)
if have uv; then
  uv tool upgrade --all &
fi

# 7) Rust toolchain
if have rustup; then
  rustup update || true
fi

# 8) Cargo‑based updaters
if have cargo-updater; then
  cargo updater -u || true
elif have cargo-list; then
  cargo list -u -a -I || true
else
  cargo install-update -a -g -j 16 || true
fi

# 9) Oh My Fish (background)
if have omf; then
  omf update || true &
fi

#–– 10) Fisher (inside fish)
if have fish; then
  fish -c 'fisher update' || true
fi

#fisher update || true ; or curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
[ -d "$HOME/.basher" ] && git -C "$HOME/.basher" pull || echo "Failed to pull from $HOME/.basher"

# 10) basher (if present)
if [ -d "$HOME/.basher" ]; then
    echo "🔄 Updating $HOME/.basher…"
    git -C "$HOME/.basher" pull || echo "⚠️ basher pull failed"
fi

# 11) tldr pages in background
if have tldr; then
  tldr -u >/dev/null 2>&1 &
  $suexec tldr -u >/dev/null 2>&1 &
fi

# 12) sdboot-manage
if have sdboot-manage; then
    $suexec sdboot-manage update >/dev/null 2>&1
    $suexec sdboot-manage remove
fi

# 13) fwupd
if have fwupdmgr; then
  fwupdmgr refresh >/dev/null 2>&1 && fwupdmgr update &
fi

# 14) misc updates in background
have updatedb && $suexec updatedb
have update-desktop-database && $suexec update-desktop-database
have update-pciids && $suexec update-pciids >/dev/null 2>&1
have update-smart-drivedb && $suexec update-smart-drivedb >/dev/null 2>&1

# 15) systemd‑boot
echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && have bootctl && bootctl is-installed >/dev/null 2>&1; then
    echo "✅ systemd‑boot detected, updating…"
    $suexec bootctl update >/dev/null 2>&1 || true
    $suexec bootctl cleanup >/dev/null 2>&1
else
    echo "❌ systemd‑boot not present, skipping."
fi

echo "🔍 Checking for Limine…"
if fd limine.cfg /boot /boot/efi /mnt >/dev/null 2>&1; then
  echo "✅ Limine config found."
  have limine-update && $suexec limine-update || echo "⚠️ limine-update missing"
  have limine-mkinitcpio && $suexec limine-mkinitcpio || echo "⚠️ limine-mkinitcpio missing"
else
  echo "❌ Limine config not found; skipping."
fi

# $suexec mkinitcpio -P
# $suexec update-initramfs -u

echo "✅ All done."
