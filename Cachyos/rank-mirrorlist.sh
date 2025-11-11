#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh" || exit 1

set -euo pipefail
shopt -s nullglob globstar extglob
export LC_ALL=C LANG=C LANGUAGE=C
SHELL=/bin/bash

# Initialize privilege
PRIV_CMD=$(init_priv)
export PRIV_CMD

# Custom message functions (override common.sh for this script's style)
if [[ -t 2 ]]; then
  ALL_OFF="\e[0m" BOLD="\e[1m"
  RED="${BOLD}\e[31m" GREEN="${BOLD}\e[32m" YELLOW="${BOLD}\e[33m"
fi
readonly ALL_OFF BOLD GREEN RED YELLOW
msg(){ printf "%b==>%b%b $1%b\n" "${GREEN-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
info(){ printf "%b -->%b%b $1%b\n" "${YELLOW-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
error(){ printf "%b==> ERROR:%b%b $1%b\n" "${RED-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "${@:2}" >&2; }
die(){ (($#)) && error "$@"; exit 255; }
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
  [[ -r $file ]] || { err "${RED}Missing: $file${DEF}"; return 1; }
  log "${YLW}Ranking mirrors for '$name'...${DEF}"
  rate-mirrors stdin \
    --save="$TMP_MAIN" \
    --fetch-mirrors-timeout=300000 \
    --comment-prefix="# " \
    --output-prefix="Server = " \
    --path-to-return='$repo/os/$arch' \
    < <(grep -Eo 'https?://[^ ]+' "$file" | sort -u) \
  && install -m644 -b -S -T "$TMP_MAIN" "$file" \
  && log "${GRN}Updated: $file${DEF}" \
  || err "${RED}rate-mirrors failed for repo '$name'${DEF}"
}

rank_arch_from_url(){
  local url="${1:-$DEFAULT_ARCH_URL}" path="$MIRRORS_DIR/mirrorlist"
  log "${YLW}Fetching mirrorlist from $url${DEF}"
  # Prefer aria2 -> curl -> wget2 -> wget
  if has aria2c; then
    aria2c -q --max-tries=3 --retry-wait=1 -d "$TMP_DIR" -o dl "$url"
  elif has curl; then
    curl -sfL --retry 3 --retry-delay 1 "$url" -o "$TMP_DIR/dl"
  elif has wget2; then
    wget2 -q -O "$TMP_DIR/dl" "$url"
  elif has wget; then
    wget -qO "$TMP_DIR/dl" "$url"
  else
    die "No download tool available (aria2c, curl, wget2, wget)"
  fi || die "Download failed: $url"
  local -a urls
  mapfile -t urls < <(awk '/^#?Server/{url=$3; sub(/\$.*/,"",url); if(!seen[url]++)print url}' "$TMP_DIR/dl")
  ((${#urls[@]}>0)) || die "No server entries found"
  log "${YLW}Ranking ${#urls[@]} Arch mirrors...${DEF}"
  printf '%s\n' "${urls[@]}" \
    | rate-mirrors --save="$TMP_MAIN" stdin \
      --path-to-test="extra/os/x86_64/extra.files" \
      --path-to-return="\$repo/os/\$arch" \
      --comment-prefix="# " --output-prefix="Server = " \
  && install -m644 -b -S -T "$TMP_MAIN" "$path" \
  && log "${GRN}Updated: $path${DEF}" \
  || die "rate-mirrors failed for Arch"
}

rate_keys(){
  has keyserver-rank || return 0
  run_priv pacman-db-upgrade
  sudo keyserver-rank --yes
}

main(){
  rank_arch_from_url "${1:-}"
  rate_keys
  if has cachyos-rate-mirrors; then
    run_priv cachyos-rate-mirrors
  else
    mirroropt cachyos
  fi
  log "${YLW}Searching for other mirrorlists...${DEF}"
  local f repo
  for f in "$MIRRORS_DIR"/*mirrorlist; do
    [[ -L $f || $f == "$MIRRORS_DIR/mirrorlist" ]] && continue
    repo=$(basename "$f" "-mirrorlist")
    [[ $repo == "$(basename "$f")" ]] && continue
    mirroropt "$repo" "$f"
  done
  run_priv chmod 644 "$MIRRORS_DIR"/*mirrorlist* &>/dev/null || :
  run_priv pacman -Syq --noconfirm --needed || :
  log "${GRN}All mirrorlists updated successfully.${DEF}"
}

main "$@"

if has rankmirrors; then
  local mirror_url="https://archlinux.org/mirrorlist/?country=DE&protocol=https&use_mirror_status=on"
  local mirror_data

  # Prefer aria2 -> curl -> wget2 -> wget for download
  if has aria2c; then
    mirror_data=$(aria2c -q --timeout=3 --allow-overwrite=true -d /tmp -o - "$mirror_url" 2>/dev/null || :)
  elif has curl; then
    mirror_data=$(curl -sS --max-time 3 "$mirror_url" 2>/dev/null || :)
  elif has wget2; then
    mirror_data=$(wget2 -qO- --timeout=3 "$mirror_url" 2>/dev/null || :)
  else
    mirror_data=$(wget --timeout=3 -q -O - "$mirror_url" 2>/dev/null || :)
  fi

  # Prefer sd -> sed for string replacement
  if [[ -n $mirror_data ]]; then
    if has sd; then
      echo "$mirror_data" | sd '^#Server' 'Server' | sd '^#.*' '' | \
        rankmirrors -n 15 - | run_priv tee /etc/pacman.d/mirrorlist.tmp >/dev/null
    else
      echo "$mirror_data" | sed -e 's/^#Server/Server/' -e '/^#/d' | \
        rankmirrors -n 15 - | run_priv tee /etc/pacman.d/mirrorlist.tmp >/dev/null
    fi
    run_priv mv /etc/pacman.d/mirrorlist.tmp /etc/pacman.d/mirrorlist
  fi
fi
