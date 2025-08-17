#!/usr/bin/env bash
set -u; shopt -s nullglob globstar
export LC_ALL=C LANG=C; sync
#──────────── Color & Effects ────────────
BLK='\e[30m' WHT='\e[37m'
RED='\e[31m' GRN='\e[32m'
YLW='\e[33m' BLU='\e[34m'
MGN='\e[35m' CYN='\e[36m'
DEF='\e[0m' BLD='\e[1m'
#──────────── Helpers ────────────────────
has() { command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x; x=$(command -v -- "$1" 2>/dev/null) || return; printf '%s\n' "${x##*/}"; } # Get basename of command
p() { printf '%s\n' "$@" 2>/dev/null; } # Print-echo
pe() { printf '%b\n' "$@" 2>/dev/null; } # Print-echo for color
sleepy() { read -rt "${1:-1}" -- <> <(:) &>/dev/null || :; } # Bash sleep replacement
#──────────── Banner ────────────────────
printf '\e]1;%s\a\e]2;%s\a' "Updates" "Updates" # Title
colors=(
  $'\033[38;5;117m'  # Light Blue
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;15m'   # White
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;117m'  # Light Blue
)
reset=$'\033[0m'
banner=$(cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
)
# Split banner into an array
IFS=$'\n' read -r -d '' -a banner_lines <<< "$banner"
# Total lines
lines=${#banner_lines[@]}
# Loop through each line and apply scaled trans flag colors
for i in "${!banner_lines[@]}"; do
  # Map line index to color index (scaled to 5 colors)
  color_index=$(( i * 5 / lines ))
  printf "%s%s%s\n" "${colors[color_index]}" "${banner_lines[i]}" "$DEF"
done
#──────────── Safe optimal privilege tool ────────────────────
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v || :
has "$suexec" || { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
#─────────────────────────────────────────
p 'Syncing hardware clock'
"$suexec" hwclock -w >/dev/null || :
p 'Updating mlocate database'
"$suexec" updatedb >/dev/null || :

p "🔄 System update"
if has paru; then
  aurtool="$(hasname paru)"
  auropts_base="--batchinstall --combinedupgrade --nokeepsrc"
elif has yay; then
  aurtool="$(hasname yay)"
  auropts_base="--answerclean y --answerdiff n --answeredit n --answerupgrade y"
fi
#aurtool="$(hasname paru || hasname yay)" || :

auropts=(--noconfirm --needed --bottomup --skipreview --cleanafter --removemake --sudoloop --sudo "$suexec" $auropts_base)
"$aurtool" -Sua "${auropts[@]}" 2>/dev/null || :
auropts="--noconfirm --needed --bottomup --skipreview --cleanafter --removemake --sudo ${suexec} ${auropts_base}"
"$aurtool" -Sua $auropts 2>/dev/null || :

[[ -f /var/lib/pacman/db.lck ]] && "$suexec" rm -f --preserve-root -- "/var/lib/pacman/db.lck" >/dev/null || : 
"$suexec" pacman -Sy archlinux-keyring --noconfirm --needed -q >/dev/null || : 
"$suexec" pacman -Fy --noconfirm >/dev/null || :
if [[ -v $aurtool ]]; then
  "$aurtool" -Suy $auropts 2>/dev/null || :
else
  "$suexec" pacman -Syu --noconfirm --needed 2>/dev/null || :
fi

if has topgrade; then
  p 'update using topgrade...'
  topno="(--disable={config_update,uv,pipx,shell,yazi,micro,system,rustup})"
  "$suexec" topgrade -y --skip-notify --no-retry "${topno[@]}" 2>/dev/null || :
fi
if has uv; then
  p 'UV tool upgrade...'
  uv tool upgrade --all 2>/dev/null || :
fi
if has pipx; then
  pipx upgrade-all 2>/dev/null || :
fi
if has pip; then
  p 'Upgrading pip user packages...'
  if has jq; then
    python3 -m pip list --user --outdated --format=json | jq -r '.[].name' | while read -r pkg; do
      python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    done
  else
  # Fallback: parse the human-readable format
    python3 -m pip list --user --outdated | awk 'NR>2 {print $1}' | while read -r pkg; do
      python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    done
  fi
fi

rustup_bin="$(command -v rustup 2>/dev/null)"; rustup_bin="${rustup_bin##*/}"
if [ -n "$rustup_bin" ] && [ -x "$rustup_bin" ]; then
  "$rustup_bin" update 2>/dev/null || :
else
  command rustup update 2>/dev/null || :
fi

p 'update cargo/rust binaries...'
if has cargo; then
  if cargo install-update -V >/dev/null 2>&1; then
    \cargo install-update -agi 2>/dev/null || :
  else
    # Update installed crates via default cargo tooling,
    \cargo install --list | awk '/^[[:alnum:]]/ {print $1}' | xargs cargo install 2>/dev/null || :
  fi
  if has cargo-updater; then
    \cargo updater -u 2>/dev/null || :
  fi
fi

if has micro; then
  p 'micro plugin update...'
  micro -plugin update >/dev/null || :
fi

if has npm && npm config get prefix | grep -q "$HOME" 2>/dev/null; then
  p 'Update npm global packages'
  npm update -g >/dev/null || :
fi

if has flatpak; then
  flatpak update -y --noninteractive &>/dev/null || :
fi

if has yazi; then
  p 'yazi update...'
  ya pkg upgrade >/dev/null || :
fi

p 'Updating shell environments...'
if has fish; then
  p 'update Fisher...'
  fish -c 'fisher update' || :
fi
if [[ ! -f $HOME/.config/fish/functions/fisher.fish ]]; then
  p 'Reinstall fisher...'
  #curl -fsSL4 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
  source <(curl -fsSL4 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish) && fisher install jorgebucaran/fisher
fi
if [[ -d $HOME/.basher ]]; then
    p "Updating $HOME/.basher"
    git -C "$HOME/.basher" pull >/dev/null || p "⚠️ basher pull failed"
fi
p 'update tldr pages...'
has tldr && "$suexec" tldr -u &>/dev/null &

if has fwupdmgr; then
  p 'update with fwupd...'
  fwupdmgr refresh &>/dev/null; fwupdmgr update >/dev/null || :
fi

if has sdboot-manage; then
  p 'update sdboot-manage...'
  "$suexec" sdboot-manage remove || :
  "$suexec" sdboot-manage update &>/dev/null || :
fi

p 'updating Font cache'
has fc-cache && "$suexec" fc-cache -f >/dev/null
p 'misc updates in background...'
has updatedb && "$suexec" updatedb >/dev/null || :
has update-desktop-database && "$suexec" update-desktop-database >/dev/null || :
has update-pciids && "$suexec" update-pciids &>/dev/null || :
has update-smart-drivedb && "$suexec" update-smart-drivedb &>/dev/null || :

p "🔍 Checking for systemd-boot..."
if [[ -d /sys/firmware/efi ]] && has bootctl && bootctl is-installed &>/dev/null; then
    p "✅ systemd‑boot detected, updating…"
    "$suexec" bootctl update &>/dev/null; "$suexec" bootctl cleanup &>/dev/null || :
else
    p "❌ systemd‑boot not present, skipping."
fi

p 'Try to update kernel initcpio...'
if has limine-mkinitcpio; then
 "$suexec" limine-mkinitcpio >/dev/null || :
elif has mkinitcpio; then
  "$suexec" mkinitcpio -P >/dev/null || :
elif has /usr/lib/booster/regenerate_images; then
  "$suexec" /usr/lib/booster/regenerate_images >/dev/null || :
elif has dracut-rebuild; then
  "$suexec" dracut-rebuild >/dev/null || :
else
 p 'The initramfs generator was not found, please update initramfs manually...'
fi

p "✅ All done."
