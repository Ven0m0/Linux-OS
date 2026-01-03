#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' X=$'\e[0m'
has() { command -v -- "$1" &>/dev/null; }
log() { printf '%b[*]%b %s\n' "$G" "$X" "$*"; }
die() {
  printf '%b[!]%b %s\n' "$R" "$X" "$*" >&2
  exit "${2:-1}"
}

# Backend: Termux (rish) vs PC (adb)
if [[ -d /data/data/com.termux ]]; then
  has rish || die "Install Shizuku + rish"
  ADB="rish"
else
  has adb || die "Install android-tools"
  ADB="adb shell"
fi
ash() { $ADB "$@"; }

cmd_compile() {
  local mode="${1:-speed-profile}" target="${2:-all}"
  log "Compiling ($target) mode=$mode..."
  case "$target" in
    all) ash cmd package compile -m "$mode" -a ;;
    system) ash pm list packages -s | cut -f2 -d: | xargs -n1 -P4 -I{} $ADB cmd package compile -m speed -f "{}" ;;
    select)
      for app in com.android.chrome com.google.android.youtube com.twitter.android com.instagram.android; do
        ash cmd package compile -m speed -f "$app" &>/dev/null || true
      done
      ;;
  esac
  log "Compilation complete"
}

cmd_clean() {
  log "Trimming caches..."
  ash pm trim-caches 999G
  local wa="/sdcard/Android/media/com.whatsapp/WhatsApp/Media"
  ash "[ -d '$wa' ]" && {
    log "Cleaning WhatsApp (>30d)..."
    ash "find '$wa' -type f -mtime +30 -delete" 2>/dev/null || true
  }
}

cmd_settings() {
  local file="${1:-android-settings.txt}" mode="${2:-safe}"
  [[ -f $file ]] || die "Settings file not found: $file"
  log "Applying settings from $file (mode=$mode)..."

  local skip_aggressive=0
  [[ $mode == "safe" ]] && skip_aggressive=1

  while IFS= read -r line; do
    [[ $line =~ ^# || -z $line ]] && continue
    [[ $line =~ ^\[(aggressive|samsung)\] ]] && { [[ $skip_aggressive -eq 1 ]] && continue || {
      read -r line
      continue
    }; }
    [[ $line =~ ^\[.*\] ]] && continue # Skip section headers

    # Execute command directly
    ash "$line" 2>/dev/null || true
  done <"$file"
  log "Settings applied"
}

cmd_doze() {
  local mode="${1:-safe}"
  log "Optimizing Doze ($mode)..."
  local -A cfg=(
    [light_after_inactive_to]=0 [light_pre_idle_to]=30000 [light_idle_to]=15000
    [light_idle_factor]=2 [light_max_idle_to]=60000 [sensing_to]=0
    [locating_to]=0 [motion_inactive_to]=0 [idle_after_inactive_to]=0
  )
  [[ $mode == "aggressive" ]] && cfg[inactive_to]=15000 cfg[quick_doze_delay_to]=5000 || {
    cfg[inactive_to]=30000
    cfg[quick_doze_delay_to]=10000
  }

  for k in "${!cfg[@]}"; do ash "device_config put device_idle $k ${cfg[$k]}"; done
  ash dumpsys deviceidle enable
  ash dumpsys deviceidle force-idle
}

usage() {
  cat <<'EOF'
Usage: android-optimize.sh [COMMAND] [OPTIONS]
Commands:
  all [safe|aggressive]   Full optimize (clean+compile+settings)
  compile [mode] [target] Compile apps (mode: speed-profile|speed; target: all|system|select)
  clean                   Trim caches + old WhatsApp media
  settings [file] [mode]  Apply settings (mode: safe|aggressive|samsung)
  doze [safe|aggressive]  Configure Doze mode only
EOF
  exit 1
}

[[ $# -eq 0 ]] && usage
case "$1" in
  all)
    mode="${2:-safe}"
    cmd_clean
    cmd_compile speed-profile all
    cmd_settings android-settings.txt "$mode"
    cmd_doze "$mode"
    ;;
  compile) cmd_compile "${2:-speed-profile}" "${3:-all}" ;;
  clean) cmd_clean ;;
  settings) cmd_settings "${2:-android-settings.txt}" "${3:-safe}" ;;
  doze) cmd_doze "${2:-safe}" ;;
  *) usage ;;
esac
