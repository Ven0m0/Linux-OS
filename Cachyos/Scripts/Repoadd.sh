#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# Initialize privilege tool
PRIV_CMD=$(init_priv)

declare -r CONF=/etc/pacman.conf
# chaotic
declare -r CHAOTIC_KEY=3056513887B78AEB
CHAOTIC_URLS=('https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst')
read -r -d '' CHAOTIC_BLOCK <<'EOF'
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
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

# endeavouros
read -r -d '' ENDEAVOUR_BLOCK <<'EOF'
[endeavouros]
SigLevel = Optional TrustAll
Include = /etc/pacman.d/endeavouros-mirrorlist"
EOF

PARU_PKGS=(alhp-keyring alhp-mirrorlist)
PACMAN_OPTS=(--noconfirm --needed)
PARU_OPTS=(--noconfirm --skipreview --needed)
has_header(){ local hdr="$1"; grep -qF -- "$hdr" "$CONF"; }
# append block variable (name) if header missing. uses nameref.
ensure_block(){
  local hdr="$1" blk="$2"
  has_header "$hdr" && return 0
  local -n blk="$blk_name"
  printf '%s\n' "$blk" | run_priv tee -a "$CONF" >/dev/null
}
recv_and_lsign(){
  run_priv pacman-key --keyserver keyserver.ubuntu.com -r "$CHAOTIC_KEY" &>/dev/null || :
  yes | run_priv pacman-key --lsign-key "$CHAOTIC_KEY" &>/dev/null || :
}
install_urls(){ run_priv pacman "${PACMAN_OPTS[@]}" -U "${CHAOTIC_URLS[@]}" &>/dev/null || :; }
install_alhp_via_paru(){
  if has paru; then
    paru "${PARU_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  else
    # fallback to pacman if paru not present
    run_priv pacman "${PACMAN_OPTS[@]}" -S "${PARU_PKGS[@]}" &>/dev/null || :
  fi
}
install_eos_repos(){
  local repo url tmpd
  repo=https://github.com/endeavouros-team/PKGBUILDS.git
  tmpd=$(mktemp -d) || return 1
  if has gix; then
    gix clone --depth=1 --no-tags "$repo" "$tmpd" &>/dev/null || return 1
  else
    git clone --depth=1 --filter=blob:none --no-tags "$repo" "$tmpd" &>/dev/null || return 1
  fi
  for dir in endeavouros-keyring endeavouros-mirrorlist; do
    cd "$tmpd/$dir" || return 1
    makepkg -sircC --skippgpcheck --skipchecksums --skipinteg --nocheck --noconfirm --needed &>/dev/null || return 1
  done
  # Add repo to pacman.conf if not present
  has_header '[endeavouros]' || ensure_block '[endeavouros]' ENDEAVOUR_BLOCK
  rm -rf "$tmpd"
  echo "Installed endeavouros‑keyring & mirrorlist and added repo entry"
}
# Check all repositories at once
missing_repos=()
has_header '[chaotic-aur]' || missing_repos+=(chaotic)
has_header '[artafinde]' || missing_repos+=(artafinde)
has_header '[core-x86-64-v3]' || missing_repos+=(alhp)
has_header '[endeavouros]' || missing_repos+=(endeavouros)

# Install cachyos repos if missing
if ! pacman -Qsq cachyos-mirrorlist &>/dev/null; then
  if curl https://mirror.cachyos.org/cachyos-repo.tar.xz -O; then
    tar xvf cachyos-repo.tar.xz && cd cachyos-repo || exit
    chmod +x cachyos-repo.sh && run_priv bash /cachyos-repo.sh
  fi
fi

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
  endeavouros) install_eos_repos ;;
  esac
done

# Update if any repos were added
((${#missing_repos[@]})) && {
  run_priv pacman -Syy "${PACMAN_OPTS[@]}" &>/dev/null || :
  echo 'repos added'
} || echo 'no changes'
