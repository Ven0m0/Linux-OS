#!/usr/bin/env bash
export LC_ALL=C LANG=C
#shopt -s nullglob globstar
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
has(){ command -v -- "$1" &>/dev/null; } # Check for command
hasname(){ local x=$(type -P -- "$1" 2>/dev/null) && printf '%s\n' "${x##*/}" 2>/dev/null; } # Get basename of command
xprint(){ printf '%s\n' "$*"; } # Print-echo
xexprint(){ printf '%b\n' "$*"; } # Print-echo for color
cleanup(){
  trap - EXIT
  unset LC_ALL RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
  export LANG=C.UTF-8
  [[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root -- "/var/lib/pacman/db.lck" &>/dev/null
}
trap cleanup EXIT
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
echo "Meow (> ^ <)"
#──────────── Safe optimal privilege tool ────────────────────
suexec="$(hasname sudo-rs || hasname sudo || hasname doas)"
[[ -z ${suexec:-} ]] && { p "❌ No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"
#──────────── Env ────────────────────
has dbus-launch && export "$(dbus-launch 2>/dev/null)"
SHELL="${BASH:-/bin/bash}"
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Zunstable-options -Ztune-cpu=native"
CFLAGS="-march=native -mtune=native -O3 -pipe" CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now-Wl,-z,pack-relative-relocs -Wl,-gc-sections"
export RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
sync
#─────────────────────────────────────────────────────────────
has modprobed-db && modprobed-db storesilent >/dev/null | :
has hwclock && "$suexec" hwclock -w >/dev/null || :
has updatedb && "$suexec" updatedb &>/dev/null || :
sysupdate(){
  local aurtool='' auropts_base auropts
  local LC_ALL=C LANG=C LANGUAGE=en_US
  echo -e "🔄${BLU}System update${DEF}"
  # Detect AUR helper
  if has paru; then
    auropts_base=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    auropts_base=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  fi
  aurtool="$(command -v paru 2>/dev/null || command -v yay 2>/dev/null)"
  # Ensure pacman lock is removed
  [[ -f /var/lib/pacman/db.lck ]] && "$suexec" rm -f --preserve-root -- "/var/lib/pacman/db.lck" >/dev/null || :
  # Update keyring and file databases
  "$suexec" pacman -Sy archlinux-keyring --noconfirm -q >/dev/null || :
  "$suexec" pacman -Fy --noconfirm &>/dev/null || :
  # Build AUR options array
  if [[ -n $aurtool ]]; then
    auropts=(--noconfirm --needed --mflags '--skipinteg --skippgpcheck' --bottomup --skipreview --cleanafter --removemake --sudoloop --sudo "$suexec" "${auropts_base[@]:-}")
    echo "🔄${BLU}Updating AUR packages with ${aurtool}...${DEF}"
    "$aurtool" -Suyy "${auropts[@]}" 2>/dev/null || :
    "$aurtool" -Sua "${auropts[@]}" 2>/dev/null || :
  else
    echo -e "🔄${BLU}Updating system with pacman...${DEF}"
    "$suexec" pacman -Suyy --noconfirm --needed 2>/dev/null || :
  fi
}
sysupdate || :

if has flatpak; then
  "$suexec" flatpak update -y --noninteractive --appstream &>/dev/null || :
  "$suexec" flatpak update -y --noninteractive --system --force-remove &>/dev/null || :
fi


if has topgrade; then
  echo 'update using topgrade...'
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
    echo 'update cargo binaries...'
    if cargo install-update -V &>/dev/null; then
      cargo_run install-update -agi 2>/dev/null
    else
      cargo_run install --list | grep -o '^[[:alnum:]][^ ]*' | xargs -r -n1 cargo install >/dev/null
    fi
    has cargo-updater && cargo_run updater -u >/dev/null
  fi
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly -y
fi

if has micro; then
  echo 'micro plugin update...'
  micro -plugin update >/dev/null || :
fi

if has yazi; then
  echo 'yazi update...'
  ya pkg upgrade >/dev/null || :
fi

#p 'Updating shell environments...'
#if has fish; then
  #if [[ -f $HOME/.config/fish/functions/fisher.fish ]]; then
    #echo 'update Fisher...'
    #fish -c ". $HOME/.config/fish/functions/fisher.fish && fisher update"
  #else
    #echo 'Reinstall fisher...'
    #. <(curl -fsSL4 https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish) 2>/dev/null && fisher install jorgebucaran/fisher
  #fi
#fi
if [[ -d $HOME/.basher ]]; then
  echo "Updating basher"
  LC_ALL=C git -C "$HOME/.basher" pull >/dev/null || echo "⚠️ basher pull failed"
fi

if has tldr; then
  echo 'update tldr pages...'
  "$suexec" tldr -u &>/dev/null || :
fi

if has uv; then
  uv-update(){
    echo "🔄 Updating uv itself..."
    uv self update -q &>/dev/null || echo "⚠️ Failed to update uv"
    echo "🔄 Updating uv tools..."
    if uv tool list -q &>/dev/null; then
      uv tool upgrade --all -q >/dev/null || echo "⚠️ Failed to update uv tools"
    else
      echo "✅ No uv tools installed"
    fi
    echo "🔄 Updating Python packages..."
    if command -v jq &>/dev/null; then
      # Update only outdated packages
      local pkgs=$(uv pip list --outdated --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)
      if [[ -n $pkgs ]]; then
        uv pip install --upgrade "$pkgs" >/dev/null || echo "⚠️ Failed to update packages"
      else
        echo "✅ All packages are up to date"
      fi
    else
      # Fallback: reinstall everything at latest versions
      echo "⚠️ jq not found, upgrading all packages instead"
      uv pip install --upgrade -r <(uv pip list --format freeze) || echo "⚠️ Failed to update packages"
    fi
    echo "🔄 Updating Python interpreters..."
    uv python update-shell -q
    uv python upgrade -q || echo "⚠️ Failed to update Python versions"
    echo "🎉 uv update complete"
  }
  uv-update
fi
if has pipx; then
  pipx upgrade-all >/dev/null || :
fi
if has pip; then
  echo 'Upgrading pip user packages...'
  if has jq; then
    python3 -m pip list --user --outdated --format=json 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r pkg; do
      python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    done
  else
    # Fallback: parse the human-readable format
    python3 -m pip list --user --outdated 2>/dev/null | awk 'NR>2 {print $1}' 2>/dev/null | while read -r pkg; do
      python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    done
  fi
fi
if has npm; then
  echo 'Update npm global packages'
  "$suexec" npm update -g >/dev/null || :
fi

echo 'misc updates in background'
has fc-cache && "$suexec" fc-cache -f >/dev/null || :
has chwd && "$suexec" chwd -a &>/dev/null || :
has update-desktop-database && "$suexec" update-desktop-database &>/dev/null || :
has update-pciids && "$suexec" update-pciids &>/dev/null || :
has update-smart-drivedb && "$suexec" update-smart-drivedb &>/dev/null || :
has update-ccache-links && "$suexec" update-ccache-links >/dev/null || :
has update-leap && LC_ALL=C update-leap &>/dev/null || :

if has fwupdmgr; then
  echo 'update with fwupd...'
  "$suexec" fwupdmgr refresh &>/dev/null; "$suexec" fwupdmgr update 2>/dev/null || :
fi

echo "🔍 Checking for systemd-boot"
if [[ -d /sys/firmware/efi ]] && has bootctl && "$suexec" bootctl is-installed -q &>/dev/null; then
  echo "✅ systemd-boot detected, updating"
  "$suexec" bootctl update -q &>/dev/null; "$suexec" bootctl cleanup -q &>/dev/null || :
else
  echo "❌ systemd-boot not present, skipping"
fi
if has sdboot-manage; then
  echo 'update sdboot-manage...'
  "$suexec" sdboot-manage remove 2>/dev/null || :
  "$suexec" sdboot-manage update &>/dev/null || :
fi
if has update-initramfs; then
  "$suexec" update-initramfs || :
else
  if has limine-mkinitcpio; then
    "$suexec" limine-mkinitcpio|| :
  elif has mkinitcpio; then
    "$suexec" mkinitcpio -P || :
  elif has "/usr/lib/booster/regenerate_images"; then
    "$suexec" /usr/lib/booster/regenerate_images || :
  elif has dracut-rebuild; then
    "$suexec" dracut-rebuild || :
  else
    echo -e "\e[31m The initramfs generator was not found, please update initramfs manually\e[0m"
  fi
fi
echo -e "\nAll done ✅ (> ^ <) Meow\n"
