#!/usr/bin/env bash
export LC_ALL=C LANG=C; shopt -s nullglob
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#============ Helpers ====================
has(){ [[ -x $(command -v -- "$1") ]]; } # Check for command
hasname(){ local x=$(type -P -- "$1" 2>/dev/null) && printf '%s\n' "${x##*/}" 2>/dev/null; } # Get basename of command
xprint(){ printf '%s\n' "$*"; } # Print-echo
xexprint(){ printf '%b\n' "$*"; } # Print-echo for color
cleanup(){
  trap - EXIT; unset LC_ALL RUSTFLAGS CFLAGS CXXFLAGS LDFLAGS
  [[ -f /var/lib/pacman/db.lck ]] && sudo rm -f --preserve-root -- '/var/lib/pacman/db.lck' &>/dev/null
}
trap cleanup EXIT
#============ Banner ====================
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
#============ Safe optimal privilege tool ====================
suexec="$(hasname sudo-rs || hasname sudo || hasname doas || hasname run0)"
[[ -z ${suexec:-} ]] && { echo "❌ No valid privilege escalation tool found." >&2; exit 1; }
[[ $EUID -ne 0 && $suexec =~ ^(sudo-rs|sudo)$ ]] && "$suexec" -v 2>/dev/null || :
export HOME="/home/${SUDO_USER:-$USER}"; sync
#============ Env ====================
has dbus-launch && export "$(dbus-launch)"
SHELL="${BASH:-/bin/bash}"; unset CARGO_ENCODED_RUSTFLAGS RUSTC_WORKSPACE_WRAPPER
RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
CFLAGS="-march=native -mtune=native -O3 -pipe" CXXFLAGS="$CFLAGS"
LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
CARGO_CACHE_RUSTC_INFO=1 CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true RUSTUP_TOOLCHAIN=nightly RUSTC_BOOTSTRAP=1
#=============================================================
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
  [[ -f /var/lib/pacman/sync/core.files ]] || "$suexec" pacman -Fy --noconfirm || :
  "$suexec" pacman -Fy --noconfirm &>/dev/null || :
  # Build AUR options array
  if [[ -n $aurtool ]]; then
    auropts=(--noconfirm --needed --mflags '--skipinteg --skippgpcheck' --bottomup --skipreview --cleanafter --removemake --sudoloop --sudo "$suexec" "${auropts_base[@]:-}")
    echo "🔄${BLU}Updating AUR packages with ${aurtool}...${DEF}"
    "$aurtool" -Suyy "${auropts[@]}" 2>/dev/null || :
    "$aurtool" -Sua --devel "${auropts[@]}" 2>/dev/null || :
  else
    echo -e "🔄${BLU}Updating system with pacman...${DEF}"
    "$suexec" pacman -Suyy --noconfirm --needed 2>/dev/null || :
  fi
}
sysupdate || :

if has topgrade; then
  echo 'update using topgrade...'
  topno="(--disable={config_update,system,tldr,maza,yazi,micro})"
  topnosudo="(--disable={config_update,uv,pipx,yazi,micro,system,rustup,cargo,lure,shell})"
  LC_ALL=C topgrade -cy --skip-notify --no-self-update --no-retry "${topno[@]}" 2>/dev/null || :
  LC_ALL=C "$suexec" topgrade -cy --skip-notify --no-self-update --no-retry "${topnosudo[@]}" 2>/dev/null || :
fi
if has flatpak; then
  "$suexec" flatpak update -y --noninteractive --appstream >/dev/null || :
  "$suexec" flatpak update -y --noninteractive --system --force-remove >/dev/null || :
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
    if cargo install-update -Vq; then
      cargo_run install-update -agiq
    else
      cargo_run install --list | grep -o '^[[:alnum:]][^ ]*' | xargs -r -n1 cargo install -q
    fi
    has cargo-syu && cargo_run syu -g
  fi
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
if has fish; then
  fish -c "fish_update_completions"
  [[ -r ${HOME}/.config/fish/functions/fisher.fish ]]  && fish -c ". "$HOME"/.config/fish/functions/fisher.fish; fisher update"
fi

[[ -d ${HOME}/.basher ]] && LC_ALL=C git -C "${HOME}/.basher" rev-parse --is-inside-work-tree &>/dev/null &&
  { LC_ALL=C git -C "${HOME}/.basher" pull --rebase --autostash --prune origin HEAD >/dev/null && echo "Updating basher"; } || echo "⚠️ basher pull failed"

has tldr && "$suexec" tldr -cuq

if has uv; then
  echo '🔄 Updating uv...'
  uv self update -q &>/dev/null || echo '⚠️ Failed to update uv'
  echo '🔄 Updating uv tools...'
  uv tool list -q && { uv tool upgrade --all -q || echo '⚠️ Failed to update uv tools' } || echo '✅ No uv tools installed'
  
  echo '🔄 Updating Python packages...'
  if command -v jq &>/dev/null; then
    local pkgs=$(uv pip list --outdated --format json | jq -r '.[].name')
    [[ -n ${pkgs:-} ]] && 
        uv pip install -Uq --system --no-break-system-packages --compile-bytecode --refresh --color auto "$pkgs" >/dev/null || echo "⚠️ Failed to update packages"
      else
        echo "✅ All packages are up to date"
      fi
    else
       Fallback: reinstall everything at latest versions
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

#if has pipx; then
  #pipx upgrade-all >/dev/null || :
#fi
#if has pip; then
  #echo 'Upgrading pip user packages...'
  #if has jq; then
    #python3 -m pip list --user --outdated --format=json 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r pkg; do
      #python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    #done
  #else
    # Fallback: parse the human-readable format
    #python3 -m pip list --user --outdated 2>/dev/null | awk 'NR>2 {print $1}' 2>/dev/null | while read -r pkg; do
      #python3 -m pip install --user --upgrade "$pkg" 2>/dev/null || :
    #done
  #fi
#fi
#if has npm; then
  #echo 'Update npm global packages'
  #"$suexec" npm update -g >/dev/null || :
#fi

echo 'misc updates in background'
has fc-cache && "$suexec" fc-cache -f >/dev/null || :
has chwd && "$suexec" chwd -a &>/dev/null || :
has update-desktop-database && "$suexec" update-desktop-database &>/dev/null || :
has update-pciids && "$suexec" update-pciids &>/dev/null || :
has update-smart-drivedb && "$suexec" update-smart-drivedb &>/dev/null || :
has update-ccache-links && "$suexec" update-ccache-links >/dev/null || :
has update-leap && LC_ALL=C update-leap &>/dev/null || :

if has fwupdmgr; then
  "$suexec" fwupdmgr refresh 
  "$suexec" fwupdmgr refresh -y
  "$suexec" fwupdtool update
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
