#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

#–– Helper to test for a binary in $PATH
have() { command -v "$1" &>/dev/null; }

# 1) Detect privilege executor
if have sudo-rs; then
  #subin="command sudo-rs"
  subin="$(command -v sudo-rs 2>/dev/null || :)"
elif have "sudo"; then
  #subin="command sudo"
  subin="$(command -v sudo 2>/dev/null || :)"
elif have doas; then
  #subin="command doas"
  subin="$(command -v doas 2>/dev/null || :)"
fi
#export suexec="command ${subin}"
export suexec="${subin}"

# Only run `-v` if not doas
if [[ "$subin" != "doas" ]]; then
  "${suexec}" -v 2>/dev/null || :
fi

echo "🔄 System update using pacman..."
${suexec} -Sy archlinux-keyring --noconfirm --needed -q 2>/dev/null || : 
${suexec} pacman -Syu --noconfirm --needed -q 2>/dev/null || :
echo "AUR update..."
paru -Sua --noconfirm --needed --combinedupgrade --nouseask --removemake \
--cleanafter --skipreview --nokeepsrc --sudo ${suexec} 2>/dev/null || :

if have topgrade; then
  echo "update using topgrade..."
  topno=(--disable={config_update,uv,pipx,shell,yazi,micro,system,rustup})
  ${suexec} topgrade -y --skip-notify --no-retry "${topno[@]}" 2>/dev/null || :
fi
if have uv; then
  echo "UV tool upgrade..."
  uv tool upgrade --all 2>/dev/null || :
fi
if command -v pipx &>/dev/null; then
    pipx upgrade-all 2>/dev/null || :
fi

rustup_bin="$(command -v rustup 2>/dev/null || true)"
if [ -n "$rustup_bin" ] && [ -x "$rustup_bin" ]; then
  "$rustup_bin" update &>/dev/null || :
else
  command rustup update &>/dev/null || :
fi

echo "update cargo/rust binaries..."
if have cargo-install-update; then
  cargo install-update -agi 2>/dev/null || :
fi
if have cargo-updater; then
  cargo updater -u 2>/dev/null || :
fi
if have cargo-list; then
  cargo list -uaI 2>/dev/null || : 
fi

if have micro; then
  echo "micro plugin update..."
  micro -plugin update 2>/dev/null || :
fi

# Update user-installed npm global packages
if command -v npm >/dev/null && npm config get prefix | grep -q "$HOME"; then
    npm update -g 2>/dev/null || :
fi

if command -v flatpak >/dev/null; then
  flatpak update -y --noninteractive &>/dev/null || :
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
  ${suexec} tldr -u &>/dev/null &
fi

if have fwupdmgr; then
  echo "update with fwupd..."
  fwupdmgr refresh &>/dev/null || :
  fwupdmgr update || :
fi

if have sdboot-manage; then
  echo "update sdboot-manage..."
  ${suexec} sdboot-manage update &>/dev/null || :
  ${suexec} sdboot-manage remove || :
fi
echo "misc updates in background..."
have updatedb && ${suexec} updatedb || :
have update-desktop-database && ${suexec} update-desktop-database || :
have update-pciids && ${suexec} update-pciids &>/dev/null || :
have update-smart-drivedb && ${suexec} update-smart-drivedb &>/dev/null || :

echo "🔍 Checking for systemd-boot..."
if [[ -d /sys/firmware/efi ]] && have bootctl && bootctl is-installed &>/dev/null; then
    echo "✅ systemd‑boot detected, updating…"
    ${suexec} bootctl update &>/dev/null || :
    ${suexec} bootctl cleanup &>/dev/null || :
else
    echo "❌ systemd‑boot not present, skipping."
fi

echo "Try to update kernel initcpio..."
if have limine-mkinitcpio; then
  ${suexec} limine-mkinitcpio || :
elif have mkinitcpio; then
  ${suexec} mkinitcpio -P || :
elif have /usr/lib/booster/regenerate_images; then
  ${suexec} /usr/lib/booster/regenerate_images || :
elif have dracut-rebuild; then
  ${suexec} dracut-rebuild || :
else
 printf "\\033[31m The initramfs generator was not found, please update initramfs manually...\\033[0m\\n"
fi

echo "✅ All done."
