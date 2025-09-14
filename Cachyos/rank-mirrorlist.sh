#!/usr/bin/env bash
# rank pacman mirrors (arch + other /etc/pacman.d/*mirrorlist*)
set -euo pipefail
LC_ALL=C LANG=C

# colors if tty
if [ -t 2 ]; then
  ALL_OFF="\e[0m"; BOLD="\e[1m"; RED="${BOLD}\e[31m"; GREEN="${BOLD}\e[32m"; YELLOW="${BOLD}\e[33m"
fi

msg(){ local fmt=$1; shift; printf "%b==>%b%b ${fmt}%b\n" "${GREEN-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
info(){ local fmt=$1; shift; printf "%b -->%b%b ${fmt}%b\n" "${YELLOW-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
error(){ local fmt=$1; shift; printf "%b==> ERROR:%b%b ${fmt}%b\n" "${RED-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
die(){ (($#)) && error "$@"; exit 255; }

# prereqs
[ "$(id -u)" -eq 0 ] || die "run as root"
command -v rate-mirrors >/dev/null 2>&1 || die "install rate-mirrors"
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || die "curl or wget required"

# globals
MIRRORS_DIR="/etc/pacman.d"
DEFAULT_ARCH_URL='https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on'
RATE_FLAGS=(--completion=1 --max-delay=10000)
export RATE_MIRRORS_PROTOCOL=${RATE_MIRRORS_PROTOCOL:-https}
export RATE_MIRRORS_ENTRY_COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-DE}

# temp
TMP_DIR=$(mktemp -d -p "${TMPDIR:-/dev/shm}" 2>/dev/null || mktemp -d)
TMP_MAIN="$TMP_DIR/ranked"
TMP_DL="$TMP_DIR/download"
trap 'rm -rf -- "$TMP_DIR"' EXIT HUP INT TERM

rate_repository_mirrors(){
  local repo="$1" path="$2"
  info "Ranking '%s'..." "$repo"
  if rate-mirrors --save="$TMP_MAIN" --allow-root --fetch-mirrors-timeout=300000 "$repo"; then
    cp -f --backup=simple --suffix=".bak" "$TMP_MAIN" "$path"
    msg "Updated: %s" "$path"
  else
    error "rate-mirrors failed for '%s'." "$repo"
  fi
}

rank_arch_from_url(){
  local url="$1" path="$2"
  info "Fetching %s" "$url"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$TMP_DL"
  else
    wget -qO "$TMP_DL" "$url"
  fi || die "download failed: %s" "$url"

  mapfile -t urls < <(
    awk '/^[[:space:]]*#?Server[[:space:]]*=/{ url=$3; sub(/\$.*/,"",url); if(substr(url,length(url),1)!="/") url=url"/"; if(!seen[url]++) print url }' "$TMP_DL"
  )
  [ "${#urls[@]}" -gt 0 ] || die "no Server entries in %s" "$url"

  info "Ranking %d mirrors..." "${#urls[@]}"
  printf '%s\n' "${urls[@]}" \
    | rate-mirrors --save="$TMP_MAIN" --allow-root stdin \
        --path-to-test="extra/os/x86_64/extra.files" \
        --path-to-return="\$repo/os/\$arch" \
        --comment-prefix="# " --output-prefix="Server = " \
        "${RATE_FLAGS[@]}" \
    || die "rate-mirrors failed for URL"

  [ -s "$TMP_MAIN" ] || die "no output from rate-mirrors"
  cp -f --backup=simple --suffix=".bak" "$TMP_MAIN" "$path"
  msg "Updated: %s" "$path"
}

main(){
  local arch_url="${ARCH_MIRRORS_URL:-${1:-$DEFAULT_ARCH_URL}}"
  rank_arch_from_url "$arch_url" "$MIRRORS_DIR/mirrorlist"

  info "searching other mirrorlists in %s" "$MIRRORS_DIR"
  while IFS= read -r -d '' f; do
    [ "$f" = "$MIRRORS_DIR/mirrorlist" ] && continue
    repo=${f##*/}; repo=${repo%-mirrorlist}
    [ -z "$repo" ] && continue
    rate_repository_mirrors "$repo" "$f"
  done < <(find "$MIRRORS_DIR" -maxdepth 1 -type f -name "*mirrorlist*" -print0)

  chmod 644 "$MIRRORS_DIR"/*mirrorlist* 2>/dev/null || :
  msg "done"
}

main "$@"
