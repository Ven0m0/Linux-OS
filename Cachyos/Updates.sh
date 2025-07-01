#!/bin/bash
# shellcheck shell=bash

# 1) Detect and cache privilege executor
if command -v doas > /dev/null 2>&1; then
    suexec="doas"
elif command -v sudo-rs > /dev/null 2>&1; then
    suexec="sudo-rs"
    sudo-rs -v
else
    suexec="/usr/bin/sudo"
    /usr/bin/sudo -v
fi

echo "🔄 Updating system..."
# 2) System update
$suexec pacman -Syu --noconfirm
# 3) AUR update
paru -Syu --noconfirm --combinedupgrade --nouseask -q --removemake --cleanafter --skipreview --nokeepsrc
# 4) topgrade (ignore failures)
if command -v topgrade >/dev/null 2>&1; then
    topgrade -c --disable=config_update --skip-notify \
             -y --no-retry --disable=uv --disable=pipx --disable=shell \
    || true
fi
# pipx upgrade-all
# 5) Discover updates
if command -v plasma-discover-update > /dev/null 2>&1; then
    eval "$(dbus-launch)"
    plasma-discover-update
else
    echo "plasma-discover-update (Discover) is not installed."
fi
# 6) uv tool upgrade in background
if command -v uv >/dev/null 2>&1; then
    uv tool upgrade --all &
fi
# 7) Rust toolchain
if command -v rustup >/dev/null 2>&1; then
    rustup update || true
fi

# 8) Cargo‑based updaters
if command -v cargo-updater > /dev/null 2>&1; then
    cargo-updater updater -u || true
elif command -v cargo-list > /dev/null 2>&1; then
    cargo-list list -u -a -I || true
else
    cargo-install-update install-update -a -g -j 16 || true
fi
# 9) omf update
if command -v omf >/dev/null 2>&1; then
    omf update || true
fi
#fisher update || true ; or curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
[ -d "$HOME/.basher" ] && git -C "$HOME/.basher" pull || echo "Failed to pull from $HOME/.basher"

# 10) basher (if present)
if [ -d "$HOME/.basher" ]; then
    echo "Updating $HOME/.basher…"
    git -C "$HOME/.basher" pull || echo "Failed to pull $HOME/.basher"
fi

# 11) tldr pages in background
if command -v tldr >/dev/null 2>&1; then
    tldr -u >/dev/null 2>&1 &
    $suexec tldr -u >/dev/null 2>&1 &
fi

# 12) sdboot-manage
if command -v sdboot-manage >/dev/null 2>&1; then
    $suexec sdboot-manage update >/dev/null 2>&1
    $suexec sdboot-manage remove
fi

# 13) fwupd
if command -v fwupdmgr >/dev/null 2>&1; then
    fwupdmgr refresh >/dev/null 2>&1
    fwupdmgr update
fi

# 14) misc updates in background
if command -v updatedb >/dev/null 2>&1; then
    $suexec updatedb &
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    $suexec update-desktop-database &
fi
if command -v update-pciids >/dev/null 2>&1; then
    $suexec update-pciids >/dev/null 2>&1 &
fi
if command -v update-smart-drivedb >/dev/null 2>&1; then
    $suexec update-smart-drivedb >/dev/null 2>&1 &
fi

# 15) systemd‑boot
echo "🔍 Checking for systemd-boot..."
if [ -d /sys/firmware/efi ] && command -v bootctl >/dev/null 2>&1; then
    echo "✅ systemd‑boot detected; updating…"
    $suexec bootctl update >/dev/null 2>&1 || true
    $suexec bootctl cleanup >/dev/null 2>&1
else
    echo "❌ systemd‑boot not present; skipping."
fi

echo "🔍 Checking for Limine..."
if fd limine.cfg /boot /boot/efi /mnt >/dev/null 2>&1; then
    echo "✅ Limine configuration detected."
    if command -v limine-update >/dev/null 2>&1; then
        $suexec limine-update
    else
        echo "⚠️ limine-update not found"
    fi
    if command -v limine-mkinitcpio >/dev/null 2>&1; then
        $suexec limine-mkinitcpio
    else
        $suexec "⚠️ limine-mkinitcpio not found"
    fi
else
    $suexec "❌ Limine not found; skipping"
fi

# $suexec mkinitcpio -P
# $suexec update-initramfs -u
