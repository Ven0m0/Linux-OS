#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"

has(){ command -v "$1" &>/dev/null; }
log(){ printf '%s\n' "[*] $*"; }
ok(){ printf '%s\n' "[+] $*"; }
warn(){ printf '%s\n' "[!] $*" >&2; }
err(){ printf '%s\n' "[-] $*" >&2; }

IS_TERMUX=$([[ -d /data/data/com.termux/files ]] && printf 1 || printf 0)
NPROC=$(nproc 2>/dev/null || printf 4)

detect_adb(){
  if ((IS_TERMUX)); then
    local a; a=$(has rish && printf rish || printf '')
    [[ -n $a ]] || { warn "rish not found; install Shizuku"; return 1; }
    printf '%s' "$a"
  else
    local a; a=$(has adb && printf adb || printf '')
    [[ -n $a ]] || { err "adb not found; install platform-tools"; return 1; }
    printf '%s' "$a"
  fi
}

ash(){
  local adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1
  if ((IS_TERMUX)); then
    [[ $# -eq 0 ]] && "$adb_cmd" sh || "$adb_cmd" "$@" 2>/dev/null || return 1
  else
    [[ $# -eq 0 ]] && "$adb_cmd" shell || "$adb_cmd" shell "$@" 2>/dev/null || return 1
  fi
}

device_ok(){
  local adb_cmd; adb_cmd="${ADB_CMD:-$(detect_adb)}" || return 1
  if ((IS_TERMUX)); then
    [[ -n $adb_cmd ]] || { err "rish unavailable"; return 1; }
    return 0
  fi
  "$adb_cmd" start-server &>/dev/null || :
  "$adb_cmd" get-state &>/dev/null || { err "No device connected; enable USB debugging"; return 1; }
}

apply_settings_file(){
  local file="${1:-android-settings.txt}"
  [[ -f $file ]] || { err "Settings file not found: $file"; return 1; }
  local batch=""
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^\[[^]]+\]$ ]] && continue
    batch+="$line"$'\n'
  done <"$file"
  [[ -z $batch ]] && { warn "No settings to apply"; return 0; }
  ash "$batch"
}

task_maint(){
  ash <<'EOF'
sync
cmd stats write-to-disk
settings put global fstrim_mandatory_interval 1
pm art cleanup
pm trim-caches 256G
cmd shortcut reset-all-throttling
logcat -b all -c
wm density reset
wm size reset
sm fstrim
cmd activity idle-maintenance
cmd system_update
cmd otadexopt cleanup
EOF
}

task_cleanup_fs(){
  ash 'find /sdcard /storage/emulated/0 -type f -iregex ".*\.\(log\|bak\|old\|tmp\)$" -delete 2>/dev/null || :'
  cmd_wa_clean "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media"
}

task_art(){
  local jid
  jid="$(ash 'cmd jobscheduler list-jobs android 2>/dev/null' | grep -F background-dexopt | awk '{print $2}' || :)"
  ash <<EOF
$([[ -n $jid ]] && printf "cmd jobscheduler run -f android %s\n" "$jid")
pm compile -af --full -r cmdline -m speed
pm compile -a --full -r cmdline -m speed-profile
pm art dexopt-packages -r bg-dexopt
art pr-deopt-job --run
pm bg-dexopt-job
EOF
}

task_block(){
  [[ $1 == enable ]] && ash 'cmd connectivity set-chain3-enabled true'
  [[ $1 == disable ]] && ash 'cmd connectivity set-chain3-enabled false'
  [[ $1 == block ]] && ash "cmd connectivity set-package-networking-enabled false \"$2\""
  [[ $1 == unblock ]] && ash "cmd connectivity set-package-networking-enabled true \"$2\""
}

task_perf(){ apply_settings_file "${1:-android-settings.txt}"; }

task_finalize(){
  ash <<'EOF'
am broadcast -a android.intent.action.ACTION_OPTIMIZE_DEVICE
am broadcast -a com.android.systemui.action.CLEAR_MEMORY
am kill-all
cmd activity kill-all
dumpsys batterystats --reset
EOF
}

cmd_device_all(){
  device_ok || return 1
  task_maint
  task_cleanup_fs
  task_art
  task_perf
  task_finalize
  ok "Device optimization complete"
}

cmd_monolith(){
  device_ok || return 1
  local mode="${1:-speed-profile}"
  ash "pm compile -a --full -r cmdline -m \"$mode\""
  ok "Compilation complete"
}

cmd_cache_clean(){
  device_ok || return 1
  if ((IS_TERMUX)); then
    ash 'pm list packages -3' | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} ash "pm clear --cache-only {}" &>/dev/null || :
    ash 'pm list packages -s' | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} ash "pm clear --cache-only {}" &>/dev/null || :
  else
    local adb_cmd; adb_cmd="${ADB_CMD:-$(detect_adb)}"
    "$adb_cmd" shell 'pm list packages -3' 2>/dev/null | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} "$adb_cmd" shell pm clear --cache-only {} &>/dev/null || :
    "$adb_cmd" shell 'pm list packages -s' 2>/dev/null | cut -d: -f2 | xargs -r -n1 -P"$NPROC" -I{} "$adb_cmd" shell pm clear --cache-only {} &>/dev/null || :
  fi
  ash 'pm trim-caches 128G'; ash 'logcat -b all -c'
  ok "Cache cleared"
}

cmd_wa_clean(){
  local wa_base="${1:-/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media}"
  ash <<EOF
[ -d "$wa_base" ] || exit 0
before=$(du -sm "$wa_base" 2>/dev/null | cut -f1 || printf 0)
find "$wa_base" -type f -iregex '.*\.\(jpg\|jpeg\|png\|gif\|mp4\|mov\|wmv\|flv\|webm\|mxf\|avi\|avchd\|mkv\|opus\)$' -mtime +30 -delete 2>/dev/null || :
rm -rf "$wa_base/WhatsApp AI Media"/* "$wa_base/WhatsApp Bug Report Attachments"/* "$wa_base/WhatsApp Stickers"/* 2>/dev/null || :
after=$(du -sm "$wa_base" 2>/dev/null | cut -f1 || printf 0)
printf 'Freed %s MB\n' "$((before - after))"
EOF
}

cmd_compile_speed(){
  local pkgs=(
    com.whatsapp com.snapchat.android com.instagram.android com.zhiliaoapp.musically
    app.revanced.android.youtube anddea.youtube.music com.spotify.music
    com.feelingtouch.rtd app.revenge com.supercell.clashroyale
    com.pittvandewitt.wavelet com.freestylelibre3.app.de
    com.nothing.camera com.android.htmlviewer com.android.providers.media
  )
  local batch=""
  for p in "${pkgs[@]}"; do batch+="pm compile -f --full -r cmdline -m speed $p"$'\n'; done
  ash "$batch"
}

cmd_compile_system(){
  local pkgs=(
    com.android.systemui com.nothing.launcher com.android.internal.systemui.navbar.threebutton
    com.google.android.webview com.google.android.webview.beta com.google.android.inputmethod.latin
    com.android.providers.settings com.android.server.telecom com.android.location.fused
    com.mediatek.location.lppe.main com.google.android.permissioncontroller com.android.bluetooth
  )
  local batch=""
  for p in "${pkgs[@]}"; do batch+="pm compile -f --full -r cmdline -m everything $p"$'\n'; done
  ash "$batch"
}

menu(){
  printf '\n=== Android Optimizer (device-only) ===\n'
  cat <<'EOF'
1) Full device optimize
2) Apply settings file
3) Monolith compile [mode]
4) Clear app caches
5) WhatsApp cleanup [path]
6) Compile speed apps
7) Compile system apps
q) Quit
EOF
}

interactive(){
  while :; do
    menu
    read -rp "Select: " c args
    case "$c" in
      1) cmd_device_all ;;
      2) task_perf "$args" ;;
      3) cmd_monolith "$args" ;;
      4) cmd_cache_clean ;;
      5) cmd_wa_clean "$args" ;;
      6) cmd_compile_speed ;;
      7) cmd_compile_system ;;
      q|Q) break ;;
      *) warn "Invalid" ;;
    esac
  done
  log "Done"
}

usage(){
  cat <<EOF
android-optimize.sh - Device-only optimizer (ADB or Termux+Shizuku)
Commands:
  device-all               Full device optimization (standard; includes cleanup + WA cleanup)
  apply [file]             Apply bulk settings file (default: android-settings.txt)
  monolith [mode]          Compile all apps (default: speed-profile)
  cache-clean              Clear app caches
  wa-clean [path]          WhatsApp media cleanup >30d
  compile-speed            Compile selected high-usage apps to speed
  compile-system           Compile core system apps to everything
  menu                     Interactive menu (default)
  -h|--help|help           Show this help
EOF
}

main(){
  export ADB_CMD="${ADB_CMD:-$(detect_adb || true)}"
  local cmd="${1:-menu}"
  shift || :
  case "$cmd" in
    device-all) cmd_device_all ;;
    apply) task_perf "$@" ;;
    monolith) cmd_monolith "$@" ;;
    cache-clean) cmd_cache_clean ;;
    wa-clean) cmd_wa_clean "$@" ;;
    compile-speed) cmd_compile_speed ;;
    compile-system) cmd_compile_system ;;
    menu) interactive ;;
    -h|--help|help) usage ;;
    *) err "Unknown: $cmd"; usage; exit 2 ;;
  esac
}
main "$@"
