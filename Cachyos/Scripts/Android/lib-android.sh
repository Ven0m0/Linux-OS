#!/usr/bin/env bash
# lib-android.sh - Shared library for Android optimization scripts
# Source this file to get common utilities for Android/ADB operations

# Prevent multiple sourcing
[[ -n ${__LIB_ANDROID_LOADED:-} ]] && return 0
readonly __LIB_ANDROID_LOADED=1

# === Core Settings ===
set -euo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

# === Color Palette (Trans Flag) ===
if [[ -t 1 ]]; then
  readonly BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
  readonly BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
  readonly LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
  readonly DEF=$'\e[0m' BLD=$'\e[1m' UND=$'\e[4m'
else
  readonly BLK="" RED="" GRN="" YLW="" BLU="" MGN="" CYN="" WHT=""
  readonly LBLU="" PNK="" BWHT="" DEF="" BLD="" UND=""
fi

# === Logging Functions ===
xecho() { printf '%b\n' "$*"; }

log() { xecho "${BLU}${BLD}[*]${DEF} $*"; }

msg() { xecho "${GRN}${BLD}[+]${DEF} $*"; }

warn() { xecho "${YLW}${BLD}[!]${DEF} $*" >&2; }

err() { xecho "${RED}${BLD}[-]${DEF} $*" >&2; }

die() {
  err "$1"
  exit "${2:-1}"
}

dbg() {
  [[ ${DEBUG:-0} -eq 1 ]] && xecho "${MGN}[DBG]${DEF} $*" || :
}

sec() {
  printf '\n%s%s=== %s ===%s\n' "$CYN" "$BLD" "$*" "$DEF"
}

# === Tool Detection ===
has() { command -v "$1" &>/dev/null; }

hasname() {
  local cmd
  for cmd in "$@"; do
    if has "$cmd"; then
      printf '%s' "$cmd"
      return 0
    fi
  done
  return 1
}

# === Environment Detection ===
readonly IS_TERMUX="$([[ -d /data/data/com.termux/files ]] && echo 1 || echo 0)"
readonly NPROC="$(nproc 2>/dev/null || echo 4)"

# === ADB/Device Utilities ===

# Detect ADB or rish (for Termux+Shizuku)
detect_adb() {
  local adb_cmd
  if ((IS_TERMUX)); then
    adb_cmd="$(hasname rish)" || {
      warn "rish not found; install Shizuku for device access"
      return 1
    }
  else
    adb_cmd="$(hasname adb)" || {
      err "adb not found; install Android SDK platform-tools"
      return 1
    }
  fi
  printf '%s' "$adb_cmd"
}

# Execute command on Android device (via ADB or rish)
# Usage: ash <command> or ash <<EOF ... EOF (heredoc mode)
ash() {
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1

  if ((IS_TERMUX)); then
    if [[ $# -eq 0 ]]; then
      # Heredoc mode
      "$adb_cmd" sh
    else
      # Direct command
      "$adb_cmd" "$@" 2>/dev/null || return 1
    fi
  else
    # Desktop ADB
    if [[ $# -eq 0 ]]; then
      # Heredoc mode
      "$adb_cmd" shell
    else
      "$adb_cmd" shell "$@" 2>/dev/null || return 1
    fi
  fi
}

# Validate device is accessible
device_ok() {
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1

  if ((IS_TERMUX)); then
    [[ -n $adb_cmd ]] || {
      err "rish not available; install Shizuku"
      return 1
    }
    return 0
  fi

  # Desktop ADB
  "$adb_cmd" start-server &>/dev/null || :
  "$adb_cmd" get-state &>/dev/null || {
    err "No device connected; enable USB debugging"
    return 1
  }
  return 0
}

# Wait for device with timeout
wait_for_device() {
  local timeout="${1:-30}"
  local adb_cmd
  adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1

  if ((IS_TERMUX)); then
    return 0  # Skip wait for Termux (already on device)
  fi

  log "Waiting for device (timeout: ${timeout}s)..."
  timeout "$timeout" "$adb_cmd" wait-for-device || {
    err "Device connection timeout"
    return 1
  }
  msg "Device connected"
}

# === Package Manager Detection ===
pm_detect() {
  if has paru; then printf 'paru'; return; fi
  if has yay; then printf 'yay'; return; fi
  if has pacman; then printf 'pacman'; return; fi
  if has apt; then printf 'apt'; return; fi
  if has pkg && ((IS_TERMUX)); then printf 'pkg'; return; fi
  printf ''
}

# === Confirmation Prompt ===
confirm() {
  local prompt="${1:-Continue?}"
  local default="${2:-n}"
  local reply

  while :; do
    read -rp "$prompt [y/N] " reply
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no|"") return 1 ;;
      *) warn "Please answer y or n" ;;
    esac
  done
}

# === File Operations ===
file_size() {
  stat -c "%s" "$1" 2>/dev/null || stat -f "%z" "$1" 2>/dev/null || echo 0
}

human_size() {
  local bytes="$1" scale=0
  local -a units=("B" "KB" "MB" "GB" "TB")

  while ((bytes > 1024 && scale < 4)); do
    bytes=$((bytes / 1024))
    ((scale++))
  done

  printf "%d %s" "$bytes" "${units[$scale]}"
}

# === Cleanup Trap Helpers ===
cleanup_workdir() {
  [[ -n ${WORKDIR:-} && -d ${WORKDIR:-} ]] && rm -rf "${WORKDIR}" || :
}

cleanup_mount() {
  [[ -n ${MNT_PT:-} ]] && mountpoint -q -- "${MNT_PT}" && umount -R "${MNT_PT}" || :
}

cleanup_loop() {
  [[ -n ${LOOP_DEV:-} && -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" || :
}

setup_cleanup() {
  trap 'cleanup_workdir; cleanup_mount; cleanup_loop' EXIT
  trap 'err "failed at line ${LINENO}"' ERR
}

# === Batch ADB Command Helper ===
# Executes multiple ADB commands in a single shell session (massive performance boost)
# Usage: adb_batch <<'EOF'
#   command1
#   command2
# EOF
adb_batch() {
  ash
}

# === Find Tools with Fallbacks ===
FD="${FD:-$(hasname fd fdfind || :)}"
RG="${RG:-$(hasname rg grep || :)}"
BAT="${BAT:-$(hasname bat batcat cat || :)}"
SD="${SD:-$(hasname sd || :)}"

readonly FD RG BAT SD

# === Export Functions for Subshells ===
export -f has hasname log msg warn err die dbg sec
export -f xecho confirm file_size human_size
export -f ash device_ok wait_for_device adb_batch

# === Version ===
readonly LIB_ANDROID_VERSION="1.0.0"

dbg "lib-android.sh v${LIB_ANDROID_VERSION} loaded"
