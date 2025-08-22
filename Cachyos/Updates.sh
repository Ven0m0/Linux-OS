#!/usr/bin/env bash
export LC_ALL=C LANG=C
set -x
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x=$(type -P -- "$1") || return; printf '%s\n' "${x##*/}"; } # Get basename of command
p(){ printf '%s\n' "$*" 2>/dev/null || :; } # Print-echo
pe(){ printf '%b\n' "$*" 2>/dev/null || :; } # Print-echo for color
#──────────── Banner ────────────────────
banner=$(cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
)
# Split banner into array
mapfile -t banner_lines <<< "$banner"
lines=${#banner_lines[@]}
# Trans flag gradient sequence (top→bottom) using 256 colors for accuracy
flag_colors=(
  $LBLU  # Light Blue
  $PNK   # Pink
  $BWHT  # White
  $PNK   # Pink
  $LBLU  # Light Blue
)
segments=${#flag_colors[@]}
# If banner is trivially short, just print without dividing by (lines-1)
if (( lines <= 1 )); then
  for line in "${banner_lines[@]}"; do
    printf "%s%s%s\n" "${flag_colors[0]}" "$line" "$DEF"
  done
else
  for i in "${!banner_lines[@]}"; do
    # Map line index proportionally into 0..(segments-1)
    segment_index=$(( i * (segments - 1) / (lines - 1) ))
    (( segment_index >= segments )) && segment_index=$((segments - 1))
    printf "%s%s%s\n" "${flag_colors[segment_index]}" "${banner_lines[i]}" "$DEF"
  done
fi
#──────────── Safe optimal privilege tool ────────────────────
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v
#─────────────────────────────────────────
sync
"$suexec" hwclock -w >/dev/null
"$suexec" updatedb >/dev/null

sysupdate(){
  local aurtool='' auropts_base auropts
  pe "🔄${BLU}System update${DEF}"
  # Detect AUR helper
  if has paru; then
    aurtool=paru
    auropts_base=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    aurtool=yay
    auropts_base=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  fi
  # Ensure pacman lock is removed
  [[ -f /var/lib/pacman/db.lck ]] && "$suexec" rm -f --preserve-root -- "/var/lib/pacman/db.lck" >/dev/null || :
  # Update keyring and file databases
  "$suexec" pacman -Sy archlinux-keyring --noconfirm --needed -q >/dev/null || :
  "$suexec" pacman -Fy --noconfirm >/dev/null || :
  # Build AUR options array
  if [[ -n $aurtool ]]; then
    auropts=(--noconfirm --needed --bottomup --skipreview --cleanafter --removemake --sudoloop --sudo "$suexec" "${auropts_base[@]:-}")
    pe "🔄${BLU}Updating AUR packages with ${aurtool}...${DEF}"
    "$aurtool" -Suy "${auropts[@]}" >/dev/null || :
    "$aurtool" -Sua "${auropts[@]}" >/dev/null || :
  else
    pe "🔄${BLU}Updating system with pacman...${DEF}"
    "$suexec" pacman -Syu --noconfirm --needed >/dev/null || :
  fi
}
sysupdate || :

if has flatpak; then
  flatpak update -y --noninteractive &>/dev/null || :
fi

RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Zunstable-options -Ztune-cpu=native"
CFLAGS="-march=native -mtune=native -O3 -pipe" CXXFLAGS="$CFLAGS" LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now-Wl,-z,pack-relative-relocs -Wl,-gc-sections"
export RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
if has topgrade; then
  p 'update using topgrade...'
  topno="(--disable={config_update,uv,pipx,shell,yazi,micro,system,rustup,cargo,lure})"
  "$suexec" topgrade -cy --skip-notify --no-retry "${topno[@]}" 2>/dev/null || :
fi

# Function to run cargo commands dynamically
cargo_run(){
  local bins=(gg mommy clicker) cmd=(cargo) b
  for b in "${bins[@]}"; do
    command -v "cargo-$b" &>/dev/null && cmd+=("$b")
  done
  (( ${#cmd[@]} > 1 )) || { echo "No cargo binaries available: ${bins[*]}" >&2; return 1; }
  "${cmd[@]}" "$@"
}

if has rustup; then
  "$suexec" rustup update
  if has cargo; then
    p 'update cargo binaries...'
    if cargo install-update -V &>/dev/null; then
      cargo_run install-update -agi 2>/dev/null
    else
      cargo_run install --list | awk '/^[[:alnum:]]/ {print $1}' | xargs -r -n1 cargo install >/dev/null
    fi
    has cargo-updater && cargo_run updater -u >/dev/null
  fi
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y
fi

if has micro; then
  p 'micro plugin update...'
  micro -plugin update >/dev/null || :
fi

if has yazi; then
  p 'yazi update...'
  ya pkg upgrade >/dev/null || :
fi

#p 'Updating shell environments...'
#if has fish; then
  #if [[ -f $HOME/.config/fish/functions/fisher.fish ]]; then
    #p 'update Fisher...'
    #fish -c 'fisher update 2>/dev/null || :' || :
 # else
    #p 'Reinstall fisher...'
   # source <(curl -fsSL4 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish) && fisher install jorgebucaran/fisher || :
 # fi
#fi
if [[ -d $HOME/.basher ]]; then
    p "Updating basher"
    git -C "$HOME/.basher" pull >/dev/null || p "⚠️ basher pull failed"
fi

if has tldr; then
  p 'update tldr pages...'
  "$suexec" tldr -u &>/dev/null || :
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
if has npm; then
  p 'Update npm global packages'
  npm update -g >/dev/null || :
fi

if has fwupdmgr; then
  p 'update with fwupd...'
  "$suexec" fwupdmgr refresh &>/dev/null; "$suexec" fwupdmgr update >/dev/null || :
fi
if has sdboot-manage; then
  p 'update sdboot-manage...'
  "$suexec" sdboot-manage remove 2>/dev/null || :
  "$suexec" sdboot-manage update &>/dev/null || :
fi

sudo chwd -a &>/dev/null || :

p 'updating Font cache'
has fc-cache && "$suexec" fc-cache -f >/dev/null || :
p 'misc updates in background...'
has updatedb && "$suexec" updatedb >/dev/null || :
has update-desktop-database && "$suexec" update-desktop-database >/dev/null || :
has update-pciids && "$suexec" update-pciids &>/dev/null || :
has update-smart-drivedb && "$suexec" update-smart-drivedb &>/dev/null || :

p "🔍 Checking for systemd-boot..."
if [[ -d /sys/firmware/efi ]] && has bootctl && bootctl is-installed &>/dev/null; then
  p "✅ systemd-boot detected, updating…"
  "$suexec" bootctl update &>/dev/null; "$suexec" bootctl cleanup &>/dev/null || :
else
  p "❌ systemd-boot not present, skipping."
fi

if has update-initramfs; then
  "$suexec" update-initramfs >/dev/null || :
else
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
fi
p "✅ All done."
