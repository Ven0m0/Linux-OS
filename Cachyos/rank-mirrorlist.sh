#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar extglob
export LC_ALL=C LANG=C LANGUAGE=C
SHELL=/bin/bash
if [[ -t 2 ]]; then
  ALL_OFF="\e[0m" BOLD="\e[1m"
  RED="${BOLD}\e[31m" GREEN="${BOLD}\e[32m" YELLOW="${BOLD}\e[33m"
fi
readonly ALL_OFF BOLD GREEN RED YELLOW
has(){ command -v -- "$1" &>/dev/null; }
msg(){ printf "%b==>%b%b $1%b\n" "${GREEN-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
info(){ printf "%b -->%b%b $1%b\n" "${YELLOW-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
error(){ printf "%b==> ERROR:%b%b $1%b\n" "${RED-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
die(){ (($#)) && error "$@"; exit 255; }

sudo -v
has rate-mirrors || die "'rate-mirrors' is not installed."

readonly MIRRORS_DIR=/etc/pacman.d
readonly DEFAULT_ARCH_URL='https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on'
export RATE_MIRRORS_PROTOCOL=${RATE_MIRRORS_PROTOCOL:-https} \
  RATE_MIRRORS_ENTRY_COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-DE} \
  RATE_MIRRORS_ALLOW_ROOT=true \
  RATE_MIRRORS_DISABLE_COMMENTS=true \
  RATE_MIRRORS_DISABLE_COMMENTS_IN_FILE=true \
  CONCURRENCY="$(nproc)"

TMP_DIR=$(mktemp -d -p "${TMPDIR:-/dev/shm}" 2>/dev/null || mktemp -d)
readonly TMP_MAIN="$TMP_DIR/ranked"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

mirroropt(){
  local name="$1" file="${2:-$MIRRORS_DIR/${1}-mirrorlist}"
  [[ -r $file ]] || { error "Missing: %s" "$file"; return 1; }
  info "Ranking mirrors for '%s'..." "$name"
  rate-mirrors stdin \
    --save="$TMP_MAIN" \
    --fetch-mirrors-timeout=300000 \
    --comment-prefix="# " \
    --output-prefix="Server = " \
    --path-to-return='$repo/os/$arch' \
    < <(grep -Eo 'https?://[^ ]+' "$file" | sort -u) \
  && install -m644 -b -S -T "$TMP_MAIN" "$file" \
  && msg "Updated: %s" "$file" \
  || error "rate-mirrors failed for repo '%s'" "$name"
}

rank_arch_from_url(){
  local url="${1:-$DEFAULT_ARCH_URL}" path="$MIRRORS_DIR/mirrorlist"
  info "Fetching mirrorlist from %s" "$url"
  if has curl; then
    curl -sfL --retry 3 --retry-delay 1 "$url" -o "$TMP_DIR/dl"
  elif has wget; then
    wget -qO "$TMP_DIR/dl" "$url"
  else
    die "Neither curl nor wget available"
  fi || die "Download failed: %s" "$url"
  local -a urls
  mapfile -t urls < <(awk '/^#?Server/{url=$3; sub(/\$.*/,"",url); if(!seen[url]++)print url}' "$TMP_DIR/dl")
  ((${#urls[@]}>0)) || die "No server entries found"
  info "Ranking %d Arch mirrors..." "${#urls[@]}"
  printf '%s\n' "${urls[@]}" \
    | rate-mirrors --save="$TMP_MAIN" stdin \
      --path-to-test="extra/os/x86_64/extra.files" \
      --path-to-return="\$repo/os/\$arch" \
      --comment-prefix="# " --output-prefix="Server = " \
  && install -m644 -b -S -T "$TMP_MAIN" "$path" \
  && msg "Updated: %s" "$path" \
  || die "rate-mirrors failed for Arch"
}

rate_keys(){
  has keyserver-rank || return 0
  sudo pacman-db-upgrade
  sudo keyserver-rank --yes
}

main(){
  rank_arch_from_url "${1:-}"
  rate_keys
  if has cachyos-rate-mirrors; then
    sudo cachyos-rate-mirrors
  else
    mirroropt cachyos
  fi
  info "Searching for other mirrorlists..."
  local f repo
  for f in "$MIRRORS_DIR"/*mirrorlist; do
    [[ -L $f || $f == "$MIRRORS_DIR/mirrorlist" ]] && continue
    repo=$(basename "$f" "-mirrorlist")
    [[ $repo == "$(basename "$f")" ]] && continue
    mirroropt "$repo" "$f"
  done
  sudo chmod 644 "$MIRRORS_DIR"/*mirrorlist* &>/dev/null || :
  sudo pacman -Syq --noconfirm --needed || :
  msg "All mirrorlists updated successfully."
}

main "$@"

if has rankmirrors; then
  wget --timeout=3 -q -O - "https://archlinux.org/mirrorlist/?country=DE&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | \
    rankmirrors -n 15 - | sudo tee /etc/pacman.d/mirrorlist.tmp
  sudo mv /etc/pacman.d/mirrorlist.tmp /etc/pacman.d/mirrorlist
fi
