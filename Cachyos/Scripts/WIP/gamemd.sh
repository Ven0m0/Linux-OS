#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

has() { command -v -- "$1" &>/dev/null; }
msg() { printf '%s\n' "$@"; }
log() { printf '%s\n' "$@" >&2; }
die() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}
write_sys() {
  local val=$1 path=$2
  [[ -e $path ]] || return 0
  printf '%s\n' "$val" | sudo tee "$path" >/dev/null
}
write_many() {
  local val=$1
  shift
  local p
  for p in "$@"; do write_sys "$val" "$p"; done
}

main() {
  [[ ${EUID:-1} -eq 0 ]] && die "Run as user with sudo, not root."
  has sudo || die "sudo required."
  export USE_CCACHE=1
  export PROTON_ENABLE_NGX_UPDATER=1
  export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE=on
  export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE=on
  export DXVK_NVAPI_DRS_NGX_DLSS_FG_OVERRIDE=on
  export DXVK_NVAPI_DRS_NGX_DLSS_RR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
  export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_latest
  # Reset the latency timer for all PCI devices
  sudo setpci -v -s '*:*' latency_timer=20
  sudo setpci -v -s '0:0' latency_timer=0
  # Set latency timer for all sound cards
  sudo setpci -v -d "*:*:04xx" latency_timer=80
  
  sys_writes=(
    "always:/sys/kernel/mm/transparent_hugepage/enabled"
    "within_size:/sys/kernel/mm/transparent_hugepage/shmem_enabled"
    "1:/sys/kernel/mm/ksm/use_zero_pages"
    "0:/sys/devices/system/cpu/intel_pstate/no_turbo"
    "1:/proc/sys/vm/page_lock_unfairness"
    "0:/sys/kernel/mm/transparent_hugepage/use_zero_page"
    "0:/sys/kernel/mm/transparent_hugepage/shrink_underused"
    "kyber:/sys/block/nvme0n1/queue/scheduler"
    "512:/sys/block/nvme0n1/queue/nr_requests"
    "1024:/sys/block/nvme0n1/queue/read_ahead_kb"
    "0:/sys/block/sda/queue/add_random"
    "performance:/sys/module/pcie_aspm/parameters/policy"
  )
  # https://wiki.archlinux.org/title/Gaming
  echo 0 >/proc/sys/vm/compaction_proactiveness
  echo 1 >/proc/sys/vm/watermark_boost_factor
  echo 1048576 >/proc/sys/vm/min_free_kbytes
  echo 500 >/proc/sys/vm/watermark_scale_factor
  echo 5 >/sys/kernel/mm/lru_gen/enabled
  echo 0 >/proc/sys/vm/zone_reclaim_mode
  echo madvise >/sys/kernel/mm/transparent_hugepage/enabled
  echo advise >/sys/kernel/mm/transparent_hugepage/shmem_enabled
  echo never >/sys/kernel/mm/transparent_hugepage/defrag
  echo 1 >/proc/sys/vm/page_lock_unfairness
  echo 0 >/proc/sys/kernel/sched_child_runs_first
  echo 1 >/proc/sys/kernel/sched_autogroup_enabled
  setpci -v -s '*:*' latency_timer=20
  setpci -v -s '0:0' latency_timer=0
  setpci -v -d "*:*:04xx" latency_timer=80
  export LD_BIND_NOW=1
  local entry val path
  for entry in "${sys_writes[@]}"; do
    IFS=':' read -r val path <<<"$entry"
    write_sys "$val" "$path"
  done
  governor_paths=(/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
  write_many performance "${governor_paths[@]}"
  sudo powerprofilesctl set performance &>/dev/null || true
  sudo cpupower frequency-set -g performance &>/dev/null || true
  sudo systemctl stop bluetooth.service &>/dev/null || true
  for usb_device in /sys/bus/usb/devices/*/power/control; do
    [[ -e $usb_device ]] || continue
    printf 'auto\n' | sudo tee "$usb_device" >/dev/null
  done
  write_sys 0 /proc/sys/kernel/nmi_watchdog
  write_sys 0 /sys/class/rtc/rtc0/wakealarm
  cleanup_shader_cache
  if has gamemoderun; then gamemoderun; fi
  sync
  write_sys 3 /proc/sys/vm/drop_caches
}

cleanup_shader_cache() {
  readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
  readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
  if [[ -d "${HOME}/.steam/steam" ]]; then
    steam_root="${HOME}/.steam/steam"
  elif [[ -d "$XDG_DATA_HOME/Steam" ]]; then
    steam_root="$XDG_DATA_HOME/Steam"
  else
    log "Steam not found; skipping cache cleanup."
    return 0
  fi
  msg "Found Steam at: $steam_root"
  declare -A games=([730]="cs2:Counter-Strike Global Offensive:csgo")
  readonly kill_procs=(steam steamwebhelper cs2)
  msg "Stopping Steam processes..."
  pkill -15 -x "${kill_procs[@]}" 2>/dev/null || true
  for _ in {1..10}; do
    pgrep -x "${kill_procs[@]}" >/dev/null || break
    sleep 0.5
  done
  pkill -9 -x "${kill_procs[@]}" 2>/dev/null || true
  msg "Steam stopped."
  readonly logs=("$steam_root/logs" "$steam_root/dumps")
  msg "Cleaning Steam logs..."
  local dir
  for dir in "${logs[@]}"; do
    [[ -d $dir ]] || continue
    rm -f "${dir:?}/"* 2>/dev/null || true
  done
  msg "Cleaning game caches..."
  local appid exe gamedir mod game_path t_dir
  for appid in "${!games[@]}"; do
    IFS=':' read -r exe gamedir mod <<<"${games[$appid]}"
    game_path="$steam_root/steamapps/common/$gamedir"
    [[ -d $game_path ]] || continue
    msg "  -> Cleaning $gamedir ($appid)..."
    find "$game_path" -type f -name '*.mdmp' -delete 2>/dev/null || true
    target_dirs=(
      "$game_path/game/$mod/shadercache"
      "$steam_root/steamapps/shadercache/$appid"
    )
    for t_dir in "${target_dirs[@]}"; do
      [[ -d $t_dir ]] || continue
      rm -rf "${t_dir:?}/"* 2>/dev/null || true
    done
  done
  msg "Cleaning GPU caches..."
  readonly gpu_cache_dirs=(
    "${XDG_CACHE_HOME}/mesa_shader_cache"
    "${XDG_CACHE_HOME}/nvidia/GLCache"
    "${XDG_CACHE_HOME}/nvidia/DXCache"
    "${XDG_CACHE_HOME}/nvidia/OptixCache"
    "${HOME}/.nv/ComputeCache"
    "${HOME}/.nv/GLCache"
    "${XDG_CACHE_HOME}/AMD/DxCache"
    "${XDG_CACHE_HOME}/AMD/GLCache"
    "${XDG_CACHE_HOME}/AMD/VkCache"
    "${XDG_CACHE_HOME}/Intel/ShaderCache"
    "${XDG_CACHE_HOME}/dxvk-cache"
  )
  for dir in "${gpu_cache_dirs[@]}"; do
    [[ -d $dir ]] || continue
    msg "  -> Purging ${dir##*/}"
    rm -rf "${dir:?}/"* 2>/dev/null || true
  done
  msg $'\n\033[32mCleanup complete!\033[0m'
}
main "$@"

# TODO:
#if command -v powerprofilesctl &>/dev/null; then
#  exec powerprofilesctl launch -p performance -r "Launched with optimizations" -- "$@"
#else
#  exec "$@"
#fi
