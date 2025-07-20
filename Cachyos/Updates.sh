#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C LANG=C.UTF-8
shopt -s nullglob globstar

#–– Helper to test for a binary in $PATH
have() { command -v "$1" >/dev/null 2>&1; }

# 1) Detect and cache privilege executor
hash -r
if have sudo-rs; then
  subin="command sudo-rs"
elif have "sudo"; then
  subin="command sudo"
elif have doas; then
  subin="command doas"
fi
export suexec="command ${subin}"
# Cache command path lookups
hash "${subin}" cargo git curl pacman paru

# Only run `-v` if not doas
if [[ "$subin" != "doas" ]]; then
  "${suexec}" -v || :
fi

echo "🔄 System update using pacman..."
${suexec} pacman -Syu --noconfirm || :

echo "AUR update..."
paru -Syu --noconfirm --combinedupgrade --nouseask --removemake \
  --cleanafter --skipreview --nokeepsrc --sudo $(command -v sudo) || :

if have topgrade; then
  echo "update using topgrade..."
  topno=(--disable={config_update,uv,pipx,shell,yazi,micro,system,rustup})
  ${suexec} topgrade -y --skip-notify --no-retry "${topno[@]}" || :
fi
# pipx upgrade-all
if have uv; then
  echo "UV tool upgrade..."
  uv tool upgrade --all >/dev/null 2>&1 || :
fi

if have rustup; then
  echo "update Rust toolchain..."
  # broken rn
  #rustup update || :
fi

echo "update cargo/rust binaries..."
if have cargo-install-update; then
  cargo install-update -agij"$(nproc)" || :
elif have cargo-updater; then
  cargo updater -u || :
elif have cargo-list; then
  cargo list -uaI || : 
fi

if have micro; then
  echo "micro plugin update..."
  micro -plugin update || :
fi

if have yal then
  echo "yazi update..."
  ya pkg upgrade || :
fi

if have fish; then
  echo "update Fisher..."
  fish -c 'fisher update' || :
fi
if [[ ! -f "$HOME/.config/fish/functions/fisher.fish" ]]; then
  echo "Reinstall fisher..."
  curl -fsL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
fi  

if [[ -d "$HOME/.basher" ]]; then
    echo "🔄 Updating $HOME/.basher…"
    git -C "$HOME/.basher" pull || echo "⚠️ basher pull failed"
fi

if have tldr; then
  echo "update tldr pages..."
  tldr -u >/dev/null 2>&1 &
  ${suexec} tldr -u >/dev/null 2>&1 &
fi

if have sdboot-manage; then
  echo "update sdboot-manage..."
  ${suexec} sdboot-manage update >/dev/null 2>&1
  ${suexec} sdboot-manage remove
fi

if have fwupdmgr; then
  echo "update with fwupd..."
  fwupdmgr refresh >/dev/null 2>&1 && fwupdmgr update &
fi

echo "misc updates in background..."
have updatedb && ${suexec} updatedb
have update-desktop-database && ${suexec} update-desktop-database
have update-pciids && ${suexec} update-pciids >/dev/null 2>&1
have update-smart-drivedb && ${suexec} update-smart-drivedb >/dev/null 2>&1

echo "🔍 Checking for systemd-boot..."
if [[ -d /sys/firmware/efi ]] && have bootctl && bootctl is-installed >/dev/null 2>&1; then
    echo "✅ systemd‑boot detected, updating…"
    ${suexec} bootctl update >/dev/null 2>&1 || :
    ${suexec} bootctl cleanup >/dev/null 2>&1
else
    echo "❌ systemd‑boot not present, skipping."
fi

echo "Try to update kernel initcpio..."
if have limine-mkinitcpio; then
  ${suexec} limine-mkinitcpio
elif have mkinitcpio; then
  ${suexec} mkinitcpio -P
elif have /usr/lib/booster/regenerate_images; then
  ${suexec} /usr/lib/booster/regenerate_images
elif have dracut-rebuild; then
  ${suexec} dracut-rebuild
else
 echo "The initramfs generator was not found, please update initramfs manually..."
fi

echo "✅ All done."
