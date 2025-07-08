#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C.UTF-8
shopt -s nullglob globstar

#–– Helper to test for a binary in $PATH
have() { command -v "$1" >/dev/null 2>&1; }

# 1) Detect and cache privilege executor
if have sudo-rs; then
  suexec="sudo-rs"
  sudo-rs -v || :
elif have "/usr/bin/sudo"; then
  suexec="/usr/bin/sudo"
  /usr/bin/sudo -v || :
elif have "sudo"; then
  suexec="sudo"
  sudo -v || :
elif have doas; then
  suexec="doas"
fi

echo "🔄 Updating system..."
# 2) System update
$suexec pacman -Syu --noconfirm || :
# 3) AUR update
paru -Syu --noconfirm --combinedupgrade --nouseask --removemake --cleanafter --skipreview --nokeepsrc --sudo "/usr/bin/sudo" || :
# 4) topgrade (ignore failures)
if have topgrade; then
  topgrade -c --disable=config_update --skip-notify -y \
           --no-retry --disable=uv --disable=pipx --disable=shell || :
fi
# pipx upgrade-all

# 5) UV tool upgrade (background)
if have uv; then
  uv tool upgrade --all & || :
fi

# 6) Rust toolchain
if have rustup; then
  rustup update || :
fi

# Cargo‑based updaters
if have cargo-updater; then
  cargo updater -u || :
elif have cargo-list; then
  cargo list -uaI || :
else
  cargo install-update -agj 16 || :
fi

if have micro; then
  micro -plugin update || :
end

# 9) Fisher (inside fish)
if have fish; then
  fish -c 'fisher update' || :
fi
# Reinstall fisher
#curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher

# basher (if present)
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
    $suexec bootctl update >/dev/null 2>&1 || :
    $suexec bootctl cleanup >/dev/null 2>&1
else
    echo "❌ systemd‑boot not present, skipping."
fi

# 16) Limine
echo "🔍 Checking for Limine…"
if fd limine.cfg /boot /boot/efi /mnt >/dev/null 2>&1; then
  echo "✅ Limine config found."
  have limine-update && $suexec limine-update || echo "⚠️ limine-update missing"
  have limine-mkinitcpio && $suexec limine-mkinitcpio || echo "⚠️ limine-mkinitcpio missing"
else
  echo "❌ Limine config not found; skipping."
fi

# 17) Mkinitcpio
# $suexec mkinitcpio -P
# $suexec update-initramfs -u

echo "✅ All done."
