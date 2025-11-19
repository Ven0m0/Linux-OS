#!/usr/bin/env bash
# Optimized: 2025-11-19 - Applied bash optimization techniques
# Source common library
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ $SCRIPT_DIR == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR="."
cd "$SCRIPT_DIR" || exit 1
SCRIPT_DIR="$PWD"

# ============ Inlined from lib/common.sh ============
set -euo pipefail; IFS=$'
	'; shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m' MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b
' "$*"; }
log(){ xecho "$*"; }
die(){ xecho "${RED}Error:${DEF} $*" >&2; exit 1; }
confirm(){ local msg="$1"; printf '%s [y/N]: ' "$msg" >&2; read -r ans; [[ $ans == [Yy]* ]]; }
get_priv_cmd(){ local cmd; for cmd in sudo-rs sudo doas; do if has "$cmd"; then printf '%s' "$cmd"; return 0; fi; done; [[ $EUID -eq 0 ]] || die "No privilege tool found and not running as root"; printf ''; }
init_priv(){ local priv_cmd; priv_cmd=$(get_priv_cmd); [[ -n $priv_cmd && $EUID -ne 0 ]] && "$priv_cmd" -v; printf '%s' "$priv_cmd"; }
run_priv(){ local priv_cmd="${PRIV_CMD:-}"; [[ -z $priv_cmd ]] && priv_cmd=$(get_priv_cmd); if [[ $EUID -eq 0 || -z $priv_cmd ]]; then "$@"; else "$priv_cmd" -- "$@"; fi; }
print_banner(){ local banner="$1" title="${2:-}"; local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"); local -a lines=(); while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done <<<"$banner"; local line_count=${#lines[@]} segments=${#flag_colors[@]}; if ((line_count <= 1)); then printf '%s%s%s
' "${flag_colors[0]}" "${lines[0]}" "$DEF"; else for i in "${!lines[@]}"; do local segment_index=$((i * (segments - 1) / (line_count - 1))); ((segment_index >= segments)) && segment_index=$((segments - 1)); printf '%s%s%s
' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"; done; fi; [[ -n $title ]] && xecho "$title"; }
get_update_banner(){ cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}
get_clean_banner(){ cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}
print_named_banner(){ local name="$1" title="${2:-Meow (> ^ <)}" banner; case "$name" in update) banner=$(get_update_banner) ;; clean) banner=$(get_clean_banner) ;; *) die "Unknown banner name: $name" ;; esac; print_banner "$banner" "$title"; }
setup_build_env(){ [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null; export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"; export CFLAGS="-march=native -mtune=native -O3 -pipe"; export CXXFLAGS="$CFLAGS"; export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"; export; export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always; export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1; local nproc_count; nproc_count=$(nproc 2>/dev/null || echo 4); export MAKEFLAGS="-j${nproc_count}"; export NINJAFLAGS="-j${nproc_count}"; if has clang && has clang++; then export CC=clang CXX=clang++ AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib; if has ld.lld; then export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"; fi; fi; has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"; }
run_system_maintenance(){ local cmd=$1; shift; local args=("$@"); has "$cmd" || return 0; case "$cmd" in modprobed-db) "$cmd" store &>/dev/null || :;; hwclock | updatedb | chwd) run_priv "$cmd" "${args[@]}" &>/dev/null || :;; mandb) run_priv "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :;; *) run_priv "$cmd" "${args[@]}" &>/dev/null || :;; esac; }
capture_disk_usage(){ local var_name=$1; local -n ref="$var_name"; ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'); }
find_files(){ if has fd; then fd -H "$@"; else find "$@"; fi; }
find0(){ local root="$1"; shift; if has fdf; then fdf -H -0 "$@" . "$root"; elif has fd; then fd -H -0 "$@" . "$root"; else find "$root" "$@" -print0; fi; }
_PKG_MGR_CACHED=""; _AUR_OPTS_CACHED=()
detect_pkg_manager(){ if [[ -n $_PKG_MGR_CACHED ]]; then printf '%s
' "$_PKG_MGR_CACHED"; printf '%s
' "${_AUR_OPTS_CACHED[@]}"; return 0; fi; local pkgmgr; if has paru; then pkgmgr=paru; _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc); elif has yay; then pkgmgr=yay; _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y); else pkgmgr=pacman; _AUR_OPTS_CACHED=(); fi; _PKG_MGR_CACHED=$pkgmgr; printf '%s
' "$pkgmgr"; printf '%s
' "${_AUR_OPTS_CACHED[@]}"; }
get_pkg_manager(){ if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi; printf '%s
' "$_PKG_MGR_CACHED"; }
get_aur_opts(){ if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi; printf '%s
' "${_AUR_OPTS_CACHED[@]}"; }
vacuum_sqlite(){ local db=$1 s_old s_new; [[ -f $db ]] || { printf '0
'; return; }; [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0
'; return; }; if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then printf '0
'; return; fi; s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0
'; return; }; sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || { printf '0
'; return; }; s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old; printf '%d
' "$((s_old - s_new))"; }
clean_sqlite_dbs(){ local total=0 db saved; while IFS= read -r -d '' db; do [[ -f $db ]] || continue; saved=$(vacuum_sqlite "$db" || printf '0'); ((saved > 0)) && total=$((total + saved)); done < <(find0 . -maxdepth 1 -type f); ((total > 0)) && printf '  %s
' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"; }
ensure_not_running_any(){ local timeout=6 p; local pattern=$(printf '%s|' "$@"); pattern=${pattern%|}; pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return; for p in "$@"; do pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s
' "${YLW}Waiting for ${p} to exit...${DEF}"; done; local wait_time=$timeout; while ((wait_time-- > 0)); do pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return; sleep 1; done; if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then printf '  %s
' "${RED}Killing remaining processes...${DEF}"; pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :; sleep 1; fi; }
foxdir(){ local base=$1 p; [[ -d $base ]] || return 1; if [[ -f $base/installs.ini ]]; then p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini"); [[ -n $p && -d $base/$p ]] && { printf '%s
' "$base/$p"; return 0; }; fi; if [[ -f $base/profiles.ini ]]; then p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini"); [[ -n $p && -d $base/$p ]] && { printf '%s
' "$base/$p"; return 0; }; fi; return 1; }
mozilla_profiles(){ local base=$1 p; declare -A seen; [[ -d $base ]] || return 0; if [[ -f $base/installs.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s
' "$base/$p"; seen[$p]=1; }; done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini"); fi; if [[ -f $base/profiles.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s
' "$base/$p"; seen[$p]=1; }; done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini"); fi; }
chrome_roots_for(){ case "$1" in chrome) printf '%s
' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;; chromium) printf '%s
' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;; brave) printf '%s
' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;; opera) printf '%s
' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;; *) : ;; esac; }
chrome_profiles(){ local root=$1 d; for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s
' "$d"; done; }
_expand_wildcards(){ local path=$1; local -n result_ref=$2; if [[ $path == *\** ]]; then shopt -s nullglob; local -a items=($path); for item in "${items[@]}"; do [[ -e $item ]] && result_ref+=("$item"); done; shopt -u nullglob; else [[ -e $path ]] && result_ref+=("$path"); fi; }
clean_paths(){ local paths=("$@") path; local existing_paths=(); for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done; [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :; }
clean_with_sudo(){ local paths=("$@") path; local existing_paths=(); for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done; [[ ${#existing_paths[@]} -gt 0 ]] && run_priv rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :; }
_DOWNLOAD_TOOL_CACHED=""
get_download_tool(){ local skip_aria2=0; [[ ${1:-} == --no-aria2 ]] && skip_aria2=1; if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then printf '%s' "$_DOWNLOAD_TOOL_CACHED"; return 0; fi; local tool; if [[ $skip_aria2 -eq 0 ]] && has aria2c; then tool=aria2c; elif has curl; then tool=curl; elif has wget2; then tool=wget2; elif has wget; then tool=wget; else return 1; fi; [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED=$tool; printf '%s' "$tool"; }
download_file(){ local url=$1 output=$2 tool; tool=$(get_download_tool) || return 1; case $tool in aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "${output%/*}" -o "${output##*/}" "$url" ;; curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;; wget2) wget2 -q -O "$output" "$url" ;; wget) wget -qO "$output" "$url" ;; *) return 1 ;; esac; }
cleanup_pacman_lock(){ run_priv rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
# ============ End of inlined lib/common.sh ============



# Initialize privilege tool
PRIV_CMD=$(init_priv)

# Determine the device mounted at root
ROOT_DEV=$(findmnt -n -o SOURCE /)

# Check the filesystem type of the root device
FSTYPE=$(findmnt -n -o FSTYPE /)

# If the filesystem is ext4, execute the tune2fs command
if [[ $FSTYPE == "ext4" ]]; then
  log "Root filesystem is ext4 on $ROOT_DEV"
  run_priv tune2fs -O fast_commit "$ROOT_DEV"
else
  log "Root filesystem is not ext4 (detected: $FSTYPE). Skipping tune2fs."
fi

run_priv balooctl6 disable && run_priv balooctl6 purge

log "Applying Breeze Dark theme"
kwriteconfig6 --file ~/.config/kdeglobals --group General --key ColorScheme "BreezeDark"
plasma-apply-desktoptheme breeze-dark

sed -i 's/opacity = 0.8/opacity = 1.0/' "$HOME/.config/alacritty/alacritty.toml"

# Locale
locale -a | grep -q '^en_US\.utf8$' && { export LANG='en_US.UTF-8' LANGUAGE='en_US'; } || export LANG='C.UTF-8'

run_priv curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Linux-Settings/etc/sysctl.d/99-tweak-settings.conf -o /etc/sysctl.d/99-tweak-settings.conf

log "Debloat and fixup"
run_priv pacman -Rns cachyos-v4-mirrorlist --noconfirm || :
run_priv pacman -Rns cachy-browser --noconfirm || :

log "install basher from https://github.com/basherpm/basher"
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash

# https://github.com/YurinDoctrine/arch-linux-base-setup
log "Optimize writes to the disk"
for svc in journald coredump; do
  file=/etc/systemd/${svc}.conf
  # always ensure Storage=none
  kvs=(Storage=none)
  # only for journald: also Seal=no and Audit=no
  [[ $svc == journald ]] && kvs+=(Seal=no Audit=no)
  for kv in "${kvs[@]}"; do
    if grep -qE "^#*${kv%%=*}=" "$file"; then
      sudo sed -i -E "s|^#*${kv%%=*}=.*|$kv|" "$file"
    else
      log "$kv" | run_priv tee -a "$file" >/dev/null
    fi
  done
done

log "Disable bluetooth autostart"
run_priv sed -i -e 's/AutoEnable.*/AutoEnable = false/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/FastConnectable.*/FastConnectable = false/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/ReconnectAttempts.*/ReconnectAttempts = 1/' /etc/bluetooth/main.conf
run_priv sed -i -e 's/ReconnectIntervals.*/ReconnectIntervals = 1/' /etc/bluetooth/main.conf

log "Reduce systemd timeout"
run_priv sed -i -e 's/#DefaultTimeoutStartSec.*/DefaultTimeoutStartSec=5s/g' /etc/systemd/system.conf
run_priv sed -i -e 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=5s/g' /etc/systemd/system.conf

## Set zram
run_priv sed -i -e 's/#ALGO.*/ALGO=lz4/g' /etc/default/zramswap
run_priv sed -i -e 's/PERCENT.*/PERCENT=25/g' /etc/default/zramswap

## Flush bluetooth
run_priv rm -rfd /var/lib/bluetooth/*

log "Disable plymouth"
run_priv systemctl mask plymouth-read-write.service >/dev/null 2>&1
run_priv systemctl mask plymouth-start.service >/dev/null 2>&1
run_priv systemctl mask plymouth-quit.service >/dev/null 2>&1
run_priv systemctl mask plymouth-quit-wait.service >/dev/null 2>&1

## Disable file indexer
balooctl suspend
balooctl disable
balooctl purge
run_priv systemctl disable plasma-baloorunner
for dir in "$HOME" "$HOME"/*/; do touch "$dir/.metadata_never_index" "$dir/.noindex" "$dir/.nomedia" "$dir/.trackerignore"; done

log "Enable write cache"
log "write back" | run_priv tee /sys/block/*/queue/write_cache

log "Disable logging services"
run_priv systemctl mask systemd-update-utmp.service >/dev/null 2>&1
run_priv systemctl mask systemd-update-utmp-runlevel.service >/dev/null 2>&1
run_priv systemctl mask systemd-update-utmp-shutdown.service >/dev/null 2>&1
run_priv systemctl mask systemd-journal-flush.service >/dev/null 2>&1
run_priv systemctl mask systemd-journal-catalog-update.service >/dev/null 2>&1
run_priv systemctl mask systemd-journald-dev-log.socket >/dev/null 2>&1
run_priv systemctl mask systemd-journald-audit.socket >/dev/null 2>&1
log "Disable speech-dispatcher"
run_priv systemctl disable speech-dispatcher
run_priv systemctl --global disable speech-dispatcher
log "Disable smartmontools"
run_priv systemctl disable smartmontools
run_priv systemctl --global disable smartmontools
log "Disable systemd radio service/socket"
run_priv systemctl disable systemd-rfkill.service
run_priv systemctl --global disable systemd-rfkill.service
run_priv systemctl disable systemd-rfkill.socket
run_priv systemctl --global disable systemd-rfkill.socket
log "Enable dbus-broker"
run_priv systemctl enable dbus-broker.service
run_priv systemctl --global enable dbus-broker.service
log "Disable wait online service"
log "[connectivity]
enabled=false" | run_priv tee /etc/NetworkManager/conf.d/20-connectivity.conf
run_priv systemctl mask NetworkManager-wait-online.service >/dev/null 2>&1

log "Disable GPU polling"
log "options drm_kms_helper poll=0" | run_priv tee /etc/modprobe.d/disable-gpu-polling.conf

## Improve preload
run_priv sed -i -e 's/sortstrategy =.*/sortstrategy = 0/' /etc/preload.conf

# Disable pacman logging.
run_priv sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

run_priv timedatectl set-timezone Europe/Berlin

# Don't reserve space man-pages, locales, licenses.
log "Remove useless companies"
find /usr/share/doc/ -depth -type f ! -name copyright -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.gz' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.pdf' -exec sudo rm -f {} + || :
find /usr/share/doc/ -type f -name '*.tex' -exec sudo rm -f {} + || :
find /usr/share/doc/ -depth -type d -empty -exec sudo rmdir {} + || :
run_priv rm -rfd /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
  /usr/share/linda/* /var/cache/man/* /usr/share/man/* /usr/share/X11/locale/!\(en_GB\)
run_priv rm -rfd /usr/share/locale/!\(en_GB\)
yay -Rcc --noconfirm man-pages

log "Flush flatpak database"
run_priv flatpak uninstall --unused --delete-data -y
run_priv flatpak repair

log "Compress fonts"
woff2_compress /usr/share/fonts/opentype/*/*ttf
woff2_compress /usr/share/fonts/truetype/*/*ttf
## Optimize font cache
fc-cache -rfv
## Optimize icon cache
gtk-update-icon-cache

log "Clean crash log"
run_priv rm -rfd /var/crash/*
log "Clean archived journal"
run_priv journalctl --rotate --vacuum-time=0.1
run_priv sed -i -e 's/^#ForwardToSyslog=yes/ForwardToSyslog=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToKMsg=yes/ForwardToKMsg=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToConsole=yes/ForwardToConsole=no/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#ForwardToWall=yes/ForwardToWall=no/' /etc/systemd/journald.conf
log "Compress log files"
run_priv sed -i -e 's/^#Compress=yes/Compress=yes/' /etc/systemd/journald.conf
run_priv sed -i -e 's/^#compress/compress/' /etc/logrotate.conf
log "kernel.core_pattern=/dev/null" | run_priv tee /etc/sysctl.d/50-coredump.conf

#--Disable crashes
run_priv sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/system.conf
run_priv sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/system.conf
run_priv sed -i -e 's/^#DumpCore=.*/DumpCore=no/' /etc/systemd/user.conf
run_priv sed -i -e 's/^#CrashShell=.*/CrashShell=no/' /etc/systemd/user.conf

#--Update CA
run_priv update-ca-trust

doas sh -c 'touch /etc/modprobe.d/ignore_ppc.conf; log "options processor ignore_ppc=1" >/etc/modprobe.d/ignore_ppc.conf'

doas sh -c 'touch /etc/modprobe.d/nvidia.conf; log "options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_DynamicPowerManagement=0x02" >/etc/modprobe.d/nvidia.conf'

log "options vfio_pci disable_vga=1
                   options cec debug=0
                   options kvm mmu_audit=0
                   options kvm ignore_msrs=1
                   options kvm report_ignored_msrs=0
                   options kvm kvmclock_periodic_sync=1
                   options nfs enable_ino64=1
                   options libata allow_tpm=0
                   options libata ignore_hpa=0
                   options libahci ignore_sss=1
                   options libahci skip_host_reset=1
                   options uhci-hcd debug=0
                   options usbcore usbfs_snoop=0
                   options usbcore autosuspend=10" | doas tee /etc/modprobe.d/misc.conf

log "bfq
      ntsync
      tcp_bbr
      zram" | doas tee /etc/modprobe.d/modules.conf


vscode_json_set(){
  local prop=$1 val=$2
  has python3 || { log "Skipping VSCode setting (no python3): $prop"; return; }
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name='$prop'
target=json.loads('$val')
home_dir=f'/home/{os.getenv("SUDO_USER",os.getenv("USER"))}'
settings_files=[
  f'{home_dir}/.config/Code/User/settings.json',
  f'{home_dir}/.config/VSCodium/User/settings.json',
  f'{home_dir}/.config/Void/User/settings.json',
  f'{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json'
]
for sf in settings_files:
  file=Path(sf)
  if not file.is_file(): continue
  content=file.read_text()
  if not content.strip(): content='{}'
  try: obj=json.loads(content)
  except json.JSONDecodeError: continue
  if property_name in obj and obj[property_name]==target: continue
  obj[property_name]=target
  file.write_text(json.dumps(obj,indent=2))
EOF
}
  # VSCode privacy settings
  vscode_json_set 'telemetry.telemetryLevel' '"off"'
  vscode_json_set 'telemetry.enableTelemetry' 'false'
  vscode_json_set 'telemetry.enableCrashReporter' 'false'
  vscode_json_set 'workbench.enableExperiments' 'false'
  vscode_json_set 'update.mode' '"none"'
  vscode_json_set 'update.channel' '"none"'
  vscode_json_set 'update.showReleaseNotes' 'false'
  vscode_json_set 'npm.fetchOnlinePackageInfo' 'false'
  vscode_json_set 'git.autofetch' 'false'
  vscode_json_set 'workbench.settings.enableNaturalLanguageSearch' 'false'
  vscode_json_set 'typescript.disableAutomaticTypeAcquisition' 'false'
  vscode_json_set 'workbench.experimental.editSessions.enabled' 'false'
  vscode_json_set 'workbench.experimental.editSessions.autoStore' 'false'
  vscode_json_set 'workbench.editSessions.autoResume' 'false'
  vscode_json_set 'workbench.editSessions.continueOn' 'false'
  vscode_json_set 'extensions.autoUpdate' 'false'
  vscode_json_set 'extensions.autoCheckUpdates' 'false'
  vscode_json_set 'extensions.showRecommendationsOnlyOnDemand' 'true'
