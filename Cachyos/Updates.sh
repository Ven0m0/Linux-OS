#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_COLLATE=C LC_CTYPE=C 
export LANG=C.UTF-8 
export LANGUAGE=en_US
#──────────── Color & Effects ────────────
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
DEF='\e[0m'  # Reset to default
BLD='\e[1m'  #Bold
#─────────────────────────────────────────
printf '\033[2J\033[3J\033[1;1H'; printf '\e]2;%s\a' "Updates"
p() { printf "%s\n" "$@"; }
pe() { printf "%b\n" "$@"; }

banner=$(cat <<EOF
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
)
pe "${MGN}${banner}${DEF}"

#–– Helpers
has() { command -v "$1" &>/dev/null; }

# Fully safe optimal privelege tool
suexec="$(command -v sudo-rs 2>/dev/null || command -v sudo 2>/dev/null || command -v doas 2>/dev/null || :)"
[[ "${suexec:-}" == */sudo-rs || "${suexec:-}" == */sudo ]] && "$suexec" -v || :
suexec="${suexec:-sudo}"
if ! command -v "$suexec" &>/dev/null; then
  echo "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2
  exit 1
fi
sync
p "🔄 System update using pacman..."
[[ -f /var/lib/pacman/db.lck ]] && "$suexec" rm -- "/var/lib/pacman/db.lck"

"$suexec" pacman -Sy archlinux-keyring --noconfirm --needed -q 2>/dev/null || : 
"$suexec" pacman -Syu --noconfirm --needed -q 2>/dev/null || :

p "AUR update..."
if has paru; then
  aurtool="$(command -v paru 2>/dev/null)"
  auropts="--batchinstall --combinedupgrade --nouseask --nokeepsrc"
elif has yay; then
  aurtool="$(command -v yay 2>/dev/null)"
  auropts="--noredownload --norebuild"
fi
auropts="--noconfirm --needed --bottomup --skipreview --cleanafter --removemake --sudo ${suexec} ${auropts}"
"$aurtool" -Sua $auropts 2>/dev/null || :

if has topgrade; then
  p "update using topgrade..."
  topno=(--disable={config_update,uv,pipx,shell,yazi,micro,system,rustup})
  "$suexec" topgrade -y --skip-notify --no-retry "${topno[@]}" 2>/dev/null || :
fi
if has uv; then
  p "UV tool upgrade..."
  uv tool upgrade --all 2>/dev/null || :
fi
if command -v pipx &>/dev/null; then
    pipx upgrade-all 2>/dev/null || :
fi

rustup_bin="$(command -v rustup 2>/dev/null || :)"
if [ -n "$rustup_bin" ] && [ -x "$rustup_bin" ]; then
  "$rustup_bin" update &>/dev/null || :
else
  command rustup update &>/dev/null || :
fi

p "update cargo/rust binaries..."
if has cargo-install-update; then
  cargo install-update -agi 2>/dev/null || :
elif
  # Update installed crates via default cargo tooling,
  # which works even if `cargo-install-update` is not available.
  cargo install --list | 
  awk '/^[[:alnum:]]/ {print $1}' | 
  xargs cargo install 2>/dev/null || :
fi
if has cargo-updater; then
  cargo updater -u 2>/dev/null || :
fi
if has cargo-list; then
  cargo list -uaI 2>/dev/null || : 
fi

if has micro; then
  p "micro plugin update..."
  micro -plugin update 2>/dev/null || :
fi

if has npm && npm config get prefix | grep -q "$HOME" 2>/dev/null; then
  p "Update npm global packages"
  npm update -g 2>/dev/null || :
fi

if has flatpak; then
  flatpak update -y --noninteractive &>/dev/null || :
fi

if has yazi; then
  p "yazi update..."
  ya pkg upgrade || :
fi

if has fish; then
  echo "update Fisher..."
  fish -c 'fisher update' || :
fi

if [[ ! -f "$HOME/.config/fish/functions/fisher.fish" ]]; then
  p "Reinstall fisher..."
  curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
fi

if [[ -d "$HOME/.basher" ]]; then
    p "Updating $HOME/.basher…"
    git -C "$HOME/.basher" pull || echo "⚠️ basher pull failed"
fi

if has tldr; then
  p "update tldr pages..."
  ${suexec} tldr -u &>/dev/null &
fi

if has fwupdmgr; then
  p "update with fwupd..."
  fwupdmgr refresh &>/dev/null || :
  fwupdmgr update || :
fi

if has sdboot-manage; then
  p "update sdboot-manage..."
  "$suexec" sdboot-manage update &>/dev/null || :
  "$suexec" sdboot-manage remove || :
fi
p "misc updates in background..."
has updatedb && "$suexec" updatedb || :
has update-desktop-database && "$suexec" update-desktop-database || :
has update-pciids && "$suexec" update-pciids &>/dev/null || :
has update-smart-drivedb && "$suexec" update-smart-drivedb &>/dev/null || :

p "🔍 Checking for systemd-boot..."
if [[ -d /sys/firmware/efi ]] && has bootctl && bootctl is-installed &>/dev/null; then
    echo "✅ systemd‑boot detected, updating…"
    "$suexec" bootctl update &>/dev/null; "$suexec" bootctl cleanup &>/dev/null || :
else
    echo "❌ systemd‑boot not present, skipping."
fi

p "Try to update kernel initcpio..."
if has limine-mkinitcpio; then
 "$suexec" limine-mkinitcpio || :
elif has mkinitcpio; then
  "$suexec" mkinitcpio -P || :
elif has /usr/lib/booster/regenerate_images; then
  "$suexec" /usr/lib/booster/regenerate_images 2>/dev/null || :
elif has dracut-rebuild; then
  "$suexec" dracut-rebuild 2>/dev/null || :
else
 p "The initramfs generator was not found, please update initramfs manually..."
fi

p "✅ All done."
