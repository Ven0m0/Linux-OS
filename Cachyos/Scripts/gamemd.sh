#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

# ============ Inlined from lib/common.sh ============
set -euo pipefail
IFS=$'
	'
shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m' MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b
' "$*"; }
log(){ xecho "$*"; }
die(){
  xecho "${RED}Error:${DEF} $*" >&2
  exit 1
}
confirm(){
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}
get_clean_banner(){
  cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}
print_named_banner(){
  local name="$1" title="${2:-Meow (> ^ <)}" banner
  case "$name" in update) banner=$(get_update_banner) ;; clean) banner=$(get_clean_banner) ;; *) die "Unknown banner name: $name" ;; esac
  print_banner "$banner" "$title"
}
setup_build_env(){
  [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null
  export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"
  export CFLAGS="-march=native -mtune=native -O3 -pipe"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"
  export
  export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always
  export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1
  local nproc_count
  nproc_count=$(nproc 2>/dev/null || echo 4)
  export MAKEFLAGS="-j${nproc_count}"
  export NINJAFLAGS="-j${nproc_count}"
  if has clang && has clang++; then
    export CC=clang CXX=clang++ AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib
    if has ld.lld; then export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"; fi
  fi
  has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"
}
run_system_maintenance(){
  local cmd=$1
  shift
  local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in modprobed-db) "$cmd" store &>/dev/null || : ;; hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &>/dev/null || : ;; mandb) sudo "$cmd" -q &>/dev/null || mandb -q &>/dev/null || : ;; *) sudo "$cmd" "${args[@]}" &>/dev/null || : ;; esac
}
capture_disk_usage(){
  local var_name=$1
  local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}
find_files(){ if has fd; then fd -H "$@"; else find "$@"; fi; }
find0(){
  local root="$1"
  shift
  if has fdf; then fdf -H -0 "$@" . "$root"; elif has fd; then fd -H -0 "$@" . "$root"; else find "$root" "$@" -print0; fi
}
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager(){
  if [[ -n $_PKG_MGR_CACHED ]]; then
    printf '%s
' "$_PKG_MGR_CACHED"
    printf '%s
' "${_AUR_OPTS_CACHED[@]}"
    return 0
  fi
  local pkgmgr
  if has paru; then
    pkgmgr=paru
    _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc)
  elif has yay; then
    pkgmgr=yay
    _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y)
  else
    pkgmgr=pacman
    _AUR_OPTS_CACHED=()
  fi
  _PKG_MGR_CACHED=$pkgmgr
  printf '%s
' "$pkgmgr"
  printf '%s
' "${_AUR_OPTS_CACHED[@]}"
}
get_pkg_manager(){
  if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi
  printf '%s
' "$_PKG_MGR_CACHED"
}
get_aur_opts(){
  if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi
  printf '%s
' "${_AUR_OPTS_CACHED[@]}"
}
vacuum_sqlite(){
  local db=$1 s_old s_new
  [[ -f $db ]] || {
    printf '0
'
    return
  }
  [[ -f ${db}-wal || -f ${db}-journal ]] && {
    printf '0
'
    return
  }
  # Use fixed-string grep (-F) for faster literal matching
  if ! head -c 16 "$db" 2>/dev/null | grep -qF -- 'SQLite format 3'; then
    printf '0
'
    return
  fi
  s_old=$(stat -c%s "$db" 2>/dev/null) || {
    printf '0
'
    return
  }
  sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || {
    printf '0
'
    return
  }
  s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
  printf '%d
' "$((s_old - s_new))"
}
clean_sqlite_dbs(){
  local total=0 db saved
  while IFS= read -r -d '' db; do
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 1 -type f)
  ((total > 0)) && printf '  %s
' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}
ensure_not_running_any(){
  local timeout=6 p
  local pattern=$(printf '%s|' "$@")
  pattern=${pattern%|}
  pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
  for p in "$@"; do pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s
' "${YLW}Waiting for ${p} to exit...${DEF}"; done
  local wait_time=$timeout
  while ((wait_time-- > 0)); do
    pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return
    sleep 1
  done
  if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then
    printf '  %s
' "${RED}Killing remaining processes...${DEF}"
    pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :
    sleep 1
  fi
}
foxdir(){
  local base=$1 p
  [[ -d $base ]] || return 1
  if [[ -f $base/installs.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s
' "$base/$p"
      return 0
    }
  fi
  if [[ -f $base/profiles.ini ]]; then
    p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini")
    [[ -n $p && -d $base/$p ]] && {
      printf '%s
' "$base/$p"
      return 0
    }
  fi
  return 1
}
mozilla_profiles(){
  local base=$1 p
  declare -A seen
  [[ -d $base ]] || return 0
  if [[ -f $base/installs.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && {
    printf '%s
' "$base/$p"
    seen[$p]=1
  }; done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini"); fi
  if [[ -f $base/profiles.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && {
    printf '%s
' "$base/$p"
    seen[$p]=1
  }; done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini"); fi
}
chrome_roots_for(){ case "$1" in chrome) printf '%s
' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;; chromium) printf '%s
' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;; brave) printf '%s
' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;; opera) printf '%s
' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;; *) : ;; esac }
chrome_profiles(){
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s
' "$d"; done
}
_expand_wildcards(){
  local path=$1
  local -n result_ref="$2"
  if [[ $path == *\** ]]; then
    shopt -s nullglob
    local -a items=("$path")
    for item in "${items[@]}"; do [[ -e $item ]] && result_ref+=("$item"); done
    shopt -u nullglob
  else [[ -e $path ]] && result_ref+=("$path"); fi
}
clean_paths(){
  local paths=("$@") path
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}
clean_with_sudo(){
  local paths=("$@") path
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && sudo rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}
_DOWNLOAD_TOOL_CACHED=""
# shellcheck disable=SC2120
get_download_tool(){
  local skip_aria2=0
  [[ ${1:-} == --no-aria2 ]] && skip_aria2=1
  if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then
    printf '%s' "$_DOWNLOAD_TOOL_CACHED"
    return 0
  fi
  local tool
  if [[ $skip_aria2 -eq 0 ]] && has aria2c; then tool=aria2c; elif has curl; then tool=curl; elif has wget2; then tool=wget2; elif has wget; then tool=wget; else return 1; fi
  [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED=$tool
  printf '%s' "$tool"
}
download_file(){
  local url=$1 output=$2 tool
  tool=$(get_download_tool) || return 1
  case $tool in aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "${output%/*}" -o "${output##*/}" "$url" ;; curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;; wget2) wget2 -q -O "$output" "$url" ;; wget) wget -qO "$output" "$url" ;; *) return 1 ;; esac
}
cleanup_pacman_lock(){ sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
# ============ End of inlined lib/common.sh ============

# Initialize privilege tool

# Needs testing
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/use_zero_page &>/dev/null
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/shrink_underused &>/dev/null

# Known
echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null
echo advise | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled &>/dev/null
echo 1 | sudo tee /proc/sys/vm/page_lock_unfairness &>/dev/null
echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler &>/dev/null
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null
sudo powerprofilesctl set performance &>/dev/null
sudo cpupower frequency-set -g performance &>/dev/null

echo 512 | sudo tee /sys/block/nvme0n1/queue/nr_requests &>/dev/null
echo 1024 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb &>/dev/null
echo 0 | sudo tee /sys/block/sda/queue/add_random &>/dev/null

echo performance | sudo tee /sys/module/pcie_aspm/parameters/policy &>/dev/null

# disable bluetooth
sudo systemctl stop bluetooth.service

# enable USB autosuspend
for usb_device in /sys/bus/usb/devices/*/power/control; do
  echo 'auto' | sudo tee "$usb_device" >/dev/null
done

# disable NMI watchdog
echo 0 | sudo tee /proc/sys/kernel/nmi_watchdog

# disable Wake-on-Timer
echo 0 | sudo tee /sys/class/rtc/rtc0/wakealarm

export USE_CCACHE=1

# Enable HDD write cache:
# hdparm -W 1 /dev/sdX

# Disables aggressive power-saving, but keeps APM enabled
# hdparm -B 254

# Completely disables APM
# hdparm -B 255

if command -v gamemoderun &>/dev/null; then
  gamemoderun
fi
