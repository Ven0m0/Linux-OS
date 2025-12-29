#!/usr/bin/env bash
# android-optimize.sh - Optimized Android Accelerator
set -euo pipefail; shopt -s nullglob; IFS=$'\n\t'
export LC_ALL=C LANG=C

# --- Helpers ---
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' X=$'\e[0m'
log() { printf "%b[*]%b %s\n" "$G" "$X" "$*"; }
die() { printf "%b[!]%b %s\n" "$R" "$X" "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null; }

# --- Backend Detection ---
# Auto-detects: Termux (rish/Shizuku) vs PC (ADB)
if [[ -d /data/data/com.termux ]]; then
  has rish || die "Install Shizuku + rish for Termux usage"
  ADB="rish"
else
  has adb || die "Install android-tools (adb)"
  ADB="adb shell"
fi
ash() { $ADB "$@"; }

# --- Functions ---
cmd_compile() {
  local mode="${1:-speed-profile}" target="${2:-all}"
  log "Compiling ($target) with mode: $mode..."
  if [[ $target == "all" ]]; then
    ash cmd package compile -m "$mode" -a
  elif [[ $target == "system" ]]; then
    ash pm list packages -s | cut -f2 -d: | xargs -n1 -P4 -I{} $ADB cmd package compile -m speed -f "{}"
  else
    # Specific high-performance apps
    local apps=(com.android.chrome com.google.android.youtube com.twitter.android com.instagram.android)
    for app in "${apps[@]}"; do
      ash cmd package compile -m speed -f "$app" >/dev/null 2>&1 || true
    done
  fi
  log "Compilation complete."
}

cmd_clean() {
  log "Trimming caches..."
  ash pm trim-caches 999G
  
  local wa_path="/sdcard/Android/media/com.whatsapp/WhatsApp/Media"
  if ash "[ -d '$wa_path' ]"; then
    log "Cleaning WhatsApp (>30d old)..."
    # Find and delete old media, ignoring errors
    ash "find '$wa_path' -type f -mtime +30 -delete" 2>/dev/null || true
  fi
}

cmd_settings() {
  local file="${1:-android-settings.txt}"
  [[ -f $file ]] || die "Settings file not found: $file"
  log "Applying settings from $file..."
  
  while read -r line; do
    [[ $line =~ ^# || -z $line ]] && continue
    # Format: namespace key value (e.g., global window_animation_scale 0.5)
    read -r ns key val <<< "$line"
    ash settings put "$ns" "$key" "$val"
  done < "$file"
}

usage() {
  cat <<EOF
Usage: ${0##*/} [COMMAND]
Commands:
  all             Full optimize (Clean + Compile All)
  compile [mode]  Compile all apps (default: speed-profile)
  speed           Compile specific high-use apps (speed)
  system          Compile system apps (speed)
  clean           Trim caches & old WhatsApp media
  apply [file]    Apply settings from text file
EOF
  exit 1
}

# --- Main ---
[[ $# -eq 0 ]] && usage
case "$1" in
  all)      cmd_clean; cmd_compile "speed-profile" ;;
  compile)  cmd_compile "${2:-speed-profile}" "all" ;;
  speed)    cmd_compile "speed" "select" ;;
  system)   cmd_compile "speed" "system" ;;
  clean)    cmd_clean ;;
  apply)    cmd_settings "${2:-}" ;;
  *)        usage ;;
esac
