#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
LC_ALL=C.UTF-8
sudo -v

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

has() { command -v "$1" &>/dev/null; }
has_header() {
  local hdr="$1"
  grep -qF -- "$hdr" "$CONF"
}
# append block variable (name) if header missing. uses nameref.
ensure_block() {
  local hdr="$1" blk_name="$2"
  has_header "$hdr" && return 0
  local -n blk="$blk_name"
  printf '%s\n' "$blk" | sudo tee -a "$CONF" >/dev/null
}
recv_and_lsign() {
  sudo pacman-key --keyserver keyserver.ubuntu.com -r "$CHAOTIC_KEY" &>/dev/null || :
  yes | sudo pacman-key --lsign-key "$CHAOTIC_KEY" &>/dev/null || :
}
install_urls() {
  sudo pacman "${PACMAN_OPTS[@]}" -U "${CHAOTIC_URLS[@]}" &>/dev/null || :
}
install_alhp_via_paru() {
  if has paru; then
    paru "${PARU_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  else
    # fallback to pacman if paru not present
    sudo pacman "${PACMAN_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  fi
}
# Check all repositories at once
missing_repos=()
has_header '[chaotic-aur]' || missing_repos+=(chaotic)
has_header '[artafinde]' || missing_repos+=(artafinde)
has_header '[core-x86-64-v3]' || missing_repos+=(alhp)

# Process missing repos
for repo in "${missing_repos[@]}"; do
  case $repo in
  chaotic)
    recv_and_lsign
    install_urls
    ensure_block '[chaotic-aur]' CHAOTIC_BLOCK
    ;;
  artafinde) ensure_block '[artafinde]' ARTA_BLOCK ;;
  alhp)
    install_alhp_via_paru
    ensure_block '[core-x86-64-v3]' ALHP_BLOCK
    ;;
  esac
done

# Update if any repos were added
((${#missing_repos[@]})) && {
  sudo pacman -Syyuq "${PACMAN_OPTS[@]}" &>/dev/null || :
  echo 'repos added'
} || echo 'no changes'
