#!/usr/bin/env bash
#
# Ranks pacman mirrors for Arch and other repos in /etc/pacman.d
set -euo pipefail
shopt -s nullglob # Expands to nothing if no match is found

# --- Environment ---
# Set a standard, predictable environment for script execution
export LC_ALL=C LANG=C.UTF-8

# --- Colors and Logging ---
if [[ -t 2 ]]; then
  ALL_OFF="\e[0m"; BOLD="\e[1m"; RED="${BOLD}\e[31m"; GREEN="${BOLD}\e[32m"; YELLOW="${BOLD}\e[33m"
fi
readonly ALL_OFF BOLD GREEN RED YELLOW

msg() { local fmt=$1; shift; printf "%b==>%b%b ${fmt}%b\n" "${GREEN-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
info() { local fmt=$1; shift; printf "%b -->%b%b ${fmt}%b\n" "${YELLOW-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
error() { local fmt=$1; shift; printf "%b==> ERROR:%b%b ${fmt}%b\n" "${RED-}" "${ALL_OFF-}" "${BOLD-}" "${ALL_OFF-}" "$@" >&2; }
die() { (($#)) && error "$@"; exit 255; }

# --- Prerequisites ---
(( EUID == 0 )) || die "This script must be run as root."
command -v rate-mirrors >/dev/null || die "'rate-mirrors' is not installed."

# --- Globals ---
readonly MIRRORS_DIR="/etc/pacman.d"
readonly DEFAULT_ARCH_URL='https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on'
export RATE_MIRRORS_PROTOCOL=${RATE_MIRRORS_PROTOCOL:-https}
export RATE_MIRRORS_ENTRY_COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-DE}

# --- Temporary Files ---
TMP_DIR=$(mktemp -d -p "${TMPDIR:-/dev/shm}" 2>/dev/null || mktemp -d)
readonly TMP_MAIN="${TMP_DIR}/ranked" TMP_DOWNLOAD="${TMP_DIR}/download"
trap 'rm -rf -- "${TMP_DIR}"' EXIT HUP INT TERM

# --- Functions ---
rate_repository_mirrors() {
  local repo="$1" path="$2"
  info "Ranking mirrors for '%s' repository..." "$repo"
  # Corrected flag from --per-mirror-timeout
  if rate-mirrors --save="$TMP_MAIN" --allow-root --fetch-mirrors-timeout=300000 "$repo"; then
    cp -f --backup=simple --suffix=".bak" "$TMP_MAIN" "$path"
    msg "Updated: %s" "$path"
  else
    error "rate-mirrors failed for repo '%s' [errcode=$?]." "$repo"
  fi
}

rank_arch_from_url() {
  local url="$1" path="$2"
  info "Fetching mirrorlist from %s" "$url"
  if command -v curl >/dev/null; then
    curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$TMP_DOWNLOAD"
  else # Assumes wget exists due to prerequisite check
    wget -qO "$TMP_DOWNLOAD" "$url"
  fi || die "Download failed: %s" "$url"

  # Parse URLs into an array
  mapfile -t urls < <(awk '/^#?Server/ {url=$3; sub(/\$.*/,"",url); if(!seen[url]++) print url}' "$TMP_DOWNLOAD")
  (( ${#urls[@]} > 0 )) || die "No server entries found in the fetched list from %s" "$url"

  info "Ranking %d mirrors from URL..." "${#urls[@]}"
  local -a stdin_flags=(
    --path-to-test="extra/os/x86_64/extra.files"
    --path-to-return="\$repo/os/\$arch"
    --comment-prefix="# " --output-prefix="Server = "
  )
  printf '%s\n' "${urls[@]}" |
    rate-mirrors --save="$TMP_MAIN" --allow-root stdin "${stdin_flags[@]}" ||
    die "rate-mirrors failed to process mirror list from URL."

  [[ -s $TMP_MAIN ]] || die "rate-mirrors did not produce an output file."
  cp -f --backup=simple --suffix=".bak" "$TMP_MAIN" "$path"
  msg "Updated: %s" "$path"
}

# --- Main Execution ---
main() {
  local arch_url="${ARCH_MIRRORS_URL:-${1:-$DEFAULT_ARCH_URL}}"
  rank_arch_from_url "$arch_url" "$MIRRORS_DIR/mirrorlist"

  info "Searching for other mirrorlists in %s..." "$MIRRORS_DIR"
  local f repo
  # Use a simple glob, as it's cleaner and sufficient for this directory
  for f in "$MIRRORS_DIR"/*mirrorlist; do
    # Skip symlinks and the main file we already processed
    [[ -L $f || $f == "$MIRRORS_DIR/mirrorlist" ]] && continue
    repo=$(basename "$f" "-mirrorlist")
    [[ -z $repo || $repo == "$(basename "$f")" ]] && continue # Skip if suffix wasn't removed
    rate_repository_mirrors "$repo" "$f"
  done

  chmod 644 "$MIRRORS_DIR"/*mirrorlist* 2>/dev/null || :
  msg "Script finished successfully."
}

main "$@"
