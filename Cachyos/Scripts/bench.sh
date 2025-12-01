#!/usr/bin/env bash
# Unified benchmark script for parallel commands, sorting, and file copy operations
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
has() { command -v "$1" &>/dev/null; }
xecho() { printf '%b
' "$*"; }
log() { xecho "$*"; }
die() {
  xecho "${RED}Error:${DEF} $*" >&2
  exit 1
}
confirm() {
  local msg="$1"
  printf '%s [y/N]: ' "$msg" >&2
  read -r ans
  [[ $ans == [Yy]* ]]
}
print_banner() {
  local banner="$1" title="${2:-}"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  local -a lines=()
  while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done <<<"$banner"
  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  if ((line_count <= 1)); then printf '%s%s%s
' "${flag_colors[0]}" "${lines[0]}" "$DEF"; else for i in "${!lines[@]}"; do
    local segment_index=$((i * (segments - 1) / (line_count - 1)))
    ((segment_index >= segments)) && segment_index=$((segments - 1))
    printf '%s%s%s
' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"
  done; fi
  [[ -n $title ]] && xecho "$title"
}
get_update_banner() {
  cat <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF
}
get_clean_banner() {
  cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝
EOF
}
print_named_banner() {
  local name="$1" title="${2:-Meow (> ^ <)}" banner
  case "$name" in update) banner=$(get_update_banner) ;; clean) banner=$(get_clean_banner) ;; *) die "Unknown banner name: $name" ;; esac
  print_banner "$banner" "$title"
}
setup_build_env() {
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
run_system_maintenance() {
  local cmd=$1
  shift
  local args=("$@")
  has "$cmd" || return 0
  case "$cmd" in modprobed-db) "$cmd" store &>/dev/null || : ;; hwclock | updatedb | chwd) sudo "$cmd" "${args[@]}" &>/dev/null || : ;; mandb) sudo "$cmd" -q &>/dev/null || mandb -q &>/dev/null || : ;; *) sudo "$cmd" "${args[@]}" &>/dev/null || : ;; esac
}
capture_disk_usage() {
  local var_name=$1
  local -n ref="$var_name"
  ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}
find_files() { if has fd; then fd -H "$@"; else find "$@"; fi; }
find0() {
  local root="$1"
  shift
  if has fdf; then fdf -H -0 "$@" . "$root"; elif has fd; then fd -H -0 "$@" . "$root"; else find "$root" "$@" -print0; fi
}
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager() {
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
get_pkg_manager() {
  if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi
  printf '%s
' "$_PKG_MGR_CACHED"
}
get_aur_opts() {
  if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi
  printf '%s
' "${_AUR_OPTS_CACHED[@]}"
}
vacuum_sqlite() {
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
  if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then
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
clean_sqlite_dbs() {
  local total=0 db saved
  while IFS= read -r -d '' db; do
    [[ -f $db ]] || continue
    saved=$(vacuum_sqlite "$db" || printf '0')
    ((saved > 0)) && total=$((total + saved))
  done < <(find0 . -maxdepth 1 -type f)
  ((total > 0)) && printf '  %s
' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"
}
ensure_not_running_any() {
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
foxdir() {
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
mozilla_profiles() {
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
chrome_roots_for() { case "$1" in chrome) printf '%s
' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;; chromium) printf '%s
' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;; brave) printf '%s
' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;; opera) printf '%s
' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;; *) : ;; esac }
chrome_profiles() {
  local root=$1 d
  for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s
' "$d"; done
}
_expand_wildcards() {
  local path=$1
  local -n result_ref="$2"
  if [[ $path == *\** ]]; then
    shopt -s nullglob
    local -a items=("$path")
    for item in "${items[@]}"; do [[ -e $item ]] && result_ref+=("$item"); done
    shopt -u nullglob
  else [[ -e $path ]] && result_ref+=("$path"); fi
}
clean_paths() {
  local paths=("$@") path
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}
clean_with_sudo() {
  local paths=("$@") path
  local existing_paths=()
  for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done
  [[ ${#existing_paths[@]} -gt 0 ]] && sudo rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :
}
_DOWNLOAD_TOOL_CACHED=""
get_download_tool() {
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
download_file() {
  local url=$1 output=$2 tool
  tool=$(get_download_tool) || return 1
  case $tool in aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "${output%/*}" -o "${output##*/}" "$url" ;; curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;; wget2) wget2 -q -O "$output" "$url" ;; wget) wget -qO "$output" "$url" ;; *) return 1 ;; esac
}
cleanup_pacman_lock() { sudo rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
# ============ End of inlined lib/common.sh ============

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

# Initialize privilege tool

# Usage information
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Unified benchmark script for testing parallel commands, sorting, and file copy operations.

Options:
  -p, --parallel    Run parallel command benchmarks (xargs, parallel, rust-parallel, etc.)
  -s, --sort        Run sort benchmarks with different thread counts
  -c, --copy        Run file copy benchmarks (cp, cpz, xcp, uu-cp, cpui)
  -a, --all         Run all benchmarks (default)
  -j, --json        Export results to JSON/JSONL format
  -h, --help        Show this help message

Examples:
  $0                Run all benchmarks
  $0 -p             Run only parallel command benchmarks
  $0 -s -c          Run sort and copy benchmarks
  $0 -a -j          Run all benchmarks and export to JSON

Note: hyperfine must be installed to run benchmarks.
EOF
  exit 0
}

# Parse command line arguments
RUN_PARALLEL=0
RUN_SORT=0
RUN_COPY=0
EXPORT_JSON=0

if [[ $# -eq 0 ]]; then
  RUN_PARALLEL=1
  RUN_SORT=1
  RUN_COPY=0 # Copy requires specific test files
fi

while [[ $# -gt 0 ]]; do
  case $1 in
  -p | --parallel)
    RUN_PARALLEL=1
    shift
    ;;
  -s | --sort)
    RUN_SORT=1
    shift
    ;;
  -c | --copy)
    RUN_COPY=1
    shift
    ;;
  -a | --all)
    RUN_PARALLEL=1
    RUN_SORT=1
    RUN_COPY=1
    shift
    ;;
  -j | --json)
    EXPORT_JSON=1
    shift
    ;;
  -h | --help) usage ;;
  *)
    log "${RED}Unknown option: $1${DEF}"
    usage
    ;;
  esac
done

# Check for hyperfine
has hyperfine || die "hyperfine not found in PATH. Please install it first."

# Cache nproc result to avoid repeated calls
nproc_count="$(nproc 2>/dev/null || echo 1)"
jobs16="$nproc_count"
jobs8="$((nproc_count / 2))"
((jobs8 < 1)) && jobs8=1

# Save original turbo state
if [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
  o1="$(</sys/devices/system/cpu/intel_pstate/no_turbo)"
  Reset() {
    echo "$o1" | sudo tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :
  }
  # Set performance mode
  sudo cpupower frequency-set --governor performance &>/dev/null || :
  echo 1 | sudo tee "/sys/devices/system/cpu/intel_pstate/no_turbo" &>/dev/null || :
else
  Reset() { :; }
  sudo cpupower frequency-set --governor performance &>/dev/null || :
fi

# Benchmark function for parallel/sort tests
benchmark() {
  local name="$1"
  shift
  local cmd="$*"
  log "${BLU}▶${DEF} $name"
  command hyperfine -w 25 -m 50 -i -S bash \
    -p "sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null; resolvectl flush-caches &>/dev/null || :; hash -r" \
    "$cmd"
}

# Benchmark function for copy tests with JSON export
benchmark_copy() {
  local name="$1"
  shift
  local cmd="$*"

  log "${BLU}▶${DEF} $name"

  if [[ $EXPORT_JSON -eq 1 ]]; then
    hyperfine \
      --warmup 5 \
      --prepare "sudo fstrim -a --quiet-unsupported &>/dev/null; sudo journalctl --vacuum-time=1s &>/dev/null; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null" \
      --export-json /tmp/hf-"$name".json \
      "$cmd"

    if [[ -f /tmp/hf-"$name".json ]]; then
      jq -c '{cmd: .command, mean: .results[0].mean, stddev: .results[0].stddev}' \
        /tmp/hf-"$name".json >>"$LOG"
      rm -f /tmp/hf-"$name".json
    fi
  else
    hyperfine \
      --warmup 5 \
      --prepare "sudo fstrim -a --quiet-unsupported &>/dev/null; sudo journalctl --vacuum-time=1s &>/dev/null; sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null" \
      "$cmd"
  fi
}

# Initialize JSON log if needed
if [[ $EXPORT_JSON -eq 1 ]]; then
  LOG="bench-results-$(date -u +%Y%m%dT%H%M%SZ).jsonl"
  >"$LOG"
  log "${GRN}Results will be exported to: $LOG${DEF}"
fi

# Run parallel command benchmarks
if [[ $RUN_PARALLEL -eq 1 ]]; then
  log ""
  log "${BWHT}=== Parallel Command Benchmarks ===${DEF}"
  log ""

  has xargs && benchmark "xargs" "seq 1000 | xargs -n1 -P$nproc_count echo" || log "${YLW}⊘ xargs not available${DEF}"
  has parallel && benchmark "parallel" "seq 1000 | parallel -j $nproc_count echo {}" || log "${YLW}⊘ parallel not available${DEF}"
  has rust-parallel && benchmark "rust-parallel" "seq 1000 | rust-parallel -j $nproc_count echo {}" || log "${YLW}⊘ rust-parallel not available${DEF}"
  has parel && benchmark "parel" "parel -t $nproc_count 'seq 1000'" || log "${YLW}⊘ parel not available${DEF}"
  has parallel-sh && benchmark "parallel-sh" "parallel-sh -j $nproc_count 'seq 1000'" || log "${YLW}⊘ parallel-sh not available${DEF}"
fi

# Run sort benchmarks
if [[ $RUN_SORT -eq 1 ]]; then
  log ""
  log "${BWHT}=== Sort Benchmarks ===${DEF}"
  log ""

  benchmark "sort-$jobs16-threads" "sort -u -s --parallel=\"$jobs16\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-$jobs8-threads" "sort -u -s --parallel=\"$jobs8\" -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-4-threads" "sort -u -s --parallel=4 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-2-threads" "sort -u -s --parallel=2 -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-1-thread" "sort -u -s -S 50% /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
  benchmark "sort-default" "sort -u /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
fi

# Run copy benchmarks
if [[ $RUN_COPY -eq 1 ]]; then
  log ""
  log "${BWHT}=== File Copy Benchmarks ===${DEF}"
  log ""

  # Check if test file exists
  if [[ ! -f cachyos.iso ]]; then
    log "${YLW}Warning: cachyos.iso not found in current directory${DEF}"
    log "${YLW}Copy benchmarks require a test file named 'cachyos.iso'${DEF}"
    log "${YLW}Skipping copy benchmarks...${DEF}"
  else
    has cp && benchmark_copy "cp" "cp cachyos.iso cachyos-cp.iso --no-preserve=all -x -f" || log "${YLW}⊘ cp not available${DEF}"
    has cpz && benchmark_copy "cpz" "cpz cachyos.iso cachyos-cpz.iso -f" || log "${YLW}⊘ cpz not available${DEF}"

    if has xcp; then
      benchmark_copy "xcp-w0" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0"
      benchmark_copy "xcp-w4" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms"
      benchmark_copy "xcp-w8" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w8"
      benchmark_copy "xcp-w0-2MB-block" "xcp cachyos.iso cachyos-xcp.iso --no-progress -f --no-timestamps --no-perms -w 0 --block-size 2MB"
    else
      log "${YLW}⊘ xcp not available${DEF}"
    fi

    has uu-cp && benchmark_copy "uu-cp" "uu-cp -f --no-preserve=all cachyos.iso cachyos-uu-cp.iso" || log "${YLW}⊘ uu-cp not available${DEF}"
    has cpui && benchmark_copy "cpui" "cpui -f -y cachyos.iso cachyos-cpui.iso" || log "${YLW}⊘ cpui not available${DEF}"

    # Cleanup test files
    rm -f cachyos-*.iso &>/dev/null || :
  fi
fi

log ""
log "${GRN}✅ Benchmarks complete${DEF}"

if [[ $EXPORT_JSON -eq 1 && -f $LOG ]]; then
  log "${GRN}Results saved to: $LOG${DEF}"
fi

Reset
