#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; LC_ALL=C.UTF-8; sudo -v

declare -r CONF=/etc/pacman.conf
# chaotic
declare -r CHAOTIC_KEY=3056513887B78AEB
read -r -d '' CHAOTIC_BLOCK <<'EOF'
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

CHAOTIC_URLS=('https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst')

# artafinde
read -r -d '' ARTA_BLOCK <<'EOF'
[artafinde]
Server = https://pkgbuild.com/~artafinde/repo
EOF

# alhp
read -r -d '' ALHP_BLOCK <<'EOF'
[core-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[core]
Include = /etc/pacman.d/mirrorlist

[extra-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist

[multilib-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist
[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
PARU_PKGS=(alhp-keyring alhp-mirrorlist)
PACMAN_OPTS=(--noconfirm --needed)
PARU_OPTS=(--noconfirm --skipreview --needed)

has_header(){ local hdr="$1"; grep -qF -- "$hdr" "$CONF"; }
# append block variable (name) if header missing. uses nameref.
ensure_block(){
  local hdr="$1" blk_name="$2"
  has_header "$hdr" && return 0
  local -n blk="$blk_name"
  printf '%s\n' "$blk" | sudo tee -a "$CONF" >/dev/null
}
recv_and_lsign(){
  sudo pacman-key --keyserver keyserver.ubuntu.com --recv-keys "$CHAOTIC_KEY" &>/dev/null || :
  printf 'y\n' | sudo pacman-key --lsign-key "$CHAOTIC_KEY" &>/dev/null || :
}
install_urls(){
  sudo pacman "${PACMAN_OPTS[@]}" -U "${CHAOTIC_URLS[@]}" &>/dev/null || :
}
install_alhp_via_paru(){
  if command -v paru &>/dev/null; then
    paru "${PARU_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  else
    # fallback to pacman if paru not present
    sudo pacman "${PACMAN_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  fi
}
added=0

if ! has_header '[chaotic-aur]'; then
  recv_and_lsign
  install_urls
  ensure_block '[chaotic-aur]' CHAOTIC_BLOCK
  added=1
fi
if ! has_header '[artafinde]'; then
  ensure_block '[artafinde]' ARTA_BLOCK
  added=1
fi
if ! has_header '[core-x86-64-v3]'; then
  install_alhp_via_paru(){ install_alhp_via_paru; }
  install_alhp_via_paru
  ensure_block '[core-x86-64-v3]' ALHP_BLOCK
  added=1
fi
if (( added )); then
  sudo pacman -Syyuq "${PACMAN_OPTS[@]}" &>/dev/null || :
  printf 'repos added\n'
else
  printf 'no changes\n'
fi



