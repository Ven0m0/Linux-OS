#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
set -euo pipefail
shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m' MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD
has(){ command -v -- "$1" &>/dev/null; }
xecho(){ printf '%b\m' "$*"; }
log(){ xecho "$*"; }
die(){ xecho "${RED}Error:${DEF} $*" >&2; exit 1; }
confirm(){
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}
get_clean_banner(){
  cat << 'EOF'
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

echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled &>/dev/null
echo within_size | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled &>/dev/null
echo 1 | sudo tee /sys/kernel/mm/ksm/use_zero_pages &>/dev/null
echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo &>/dev/null
echo 1 | sudo tee /proc/sys/vm/page_lock_unfairness &>/dev/null
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/use_zero_page &>/dev/null
echo 0 | sudo tee /sys/kernel/mm/transparent_hugepage/shrink_underused &>/dev/null
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
