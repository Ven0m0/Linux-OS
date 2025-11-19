#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============ Inlined from lib/common.sh ============
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Export common locale settings
export LC_ALL=C LANG=C LANGUAGE=C

#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
export BLK WHT BWHT RED GRN YLW BLU CYN LBLU MGN PNK DEF BLD

#============ Core Helper Functions ============
has(){ command -v "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "$*"; }
die(){ xecho "${RED}Error:${DEF} $*" >&2; exit 1; }
confirm(){ local msg="$1"; printf '%s [y/N]: ' "$msg" >&2; read -r ans; [[ $ans == [Yy]* ]]; }

#============ Privilege Escalation ============
get_priv_cmd(){ local cmd; for cmd in sudo-rs sudo doas; do if has "$cmd"; then printf '%s' "$cmd"; return 0; fi; done; [[ $EUID -eq 0 ]] || die "No privilege tool found and not running as root"; printf ''; }
init_priv(){ local priv_cmd; priv_cmd=$(get_priv_cmd); [[ -n $priv_cmd && $EUID -ne 0 ]] && "$priv_cmd" -v; printf '%s' "$priv_cmd"; }
run_priv(){ local priv_cmd="${PRIV_CMD:-}"; [[ -z $priv_cmd ]] && priv_cmd=$(get_priv_cmd); if [[ $EUID -eq 0 || -z $priv_cmd ]]; then "$@"; else "$priv_cmd" -- "$@"; fi; }

#============ Banner Printing Functions ============
print_banner(){ local banner="$1" title="${2:-}"; local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU"); local -a lines=(); while IFS= read -r line || [[ -n $line ]]; do lines+=("$line"); done <<<"$banner"; local line_count=${#lines[@]} segments=${#flag_colors[@]}; if ((line_count <= 1)); then printf '%s%s%s\n' "${flag_colors[0]}" "${lines[0]}" "$DEF"; else for i in "${!lines[@]}"; do local segment_index=$((i * (segments - 1) / (line_count - 1))); ((segment_index >= segments)) && segment_index=$((segments - 1)); printf '%s%s%s\n' "${flag_colors[segment_index]}" "${lines[i]}" "$DEF"; done; fi; [[ -n $title ]] && xecho "$title"; }
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

#============ Build Environment Setup ============
setup_build_env(){ [[ -r /etc/makepkg.conf ]] && source /etc/makepkg.conf &>/dev/null; export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols"; export CFLAGS="-march=native -mtune=native -O3 -pipe"; export CXXFLAGS="$CFLAGS"; export LDFLAGS="-Wl,-O3 -Wl,--sort-common -Wl,--as-needed -Wl,-z,now -Wl,-z,pack-relative-relocs -Wl,-gc-sections"; export; export CARGO_CACHE_AUTO_CLEAN_FREQUENCY=always; export CARGO_HTTP_MULTIPLEXING=true CARGO_NET_GIT_FETCH_WITH_CLI=true CARGO_CACHE_RUSTC_INFO=1 RUSTC_BOOTSTRAP=1; local nproc_count; nproc_count=$(nproc 2>/dev/null || echo 4); export MAKEFLAGS="-j${nproc_count}"; export NINJAFLAGS="-j${nproc_count}"; if has clang && has clang++; then export CC=clang CXX=clang++ AR=llvm-ar NM=llvm-nm RANLIB=llvm-ranlib; if has ld.lld; then export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"; fi; fi; has dbus-launch && eval "$(dbus-launch 2>/dev/null || :)"; }

#============ System Maintenance Functions ============
run_system_maintenance(){ local cmd=$1; shift; local args=("$@"); has "$cmd" || return 0; case "$cmd" in modprobed-db) "$cmd" store &>/dev/null || :;; hwclock | updatedb | chwd) run_priv "$cmd" "${args[@]}" &>/dev/null || :;; mandb) run_priv "$cmd" -q &>/dev/null || mandb -q &>/dev/null || :;; *) run_priv "$cmd" "${args[@]}" &>/dev/null || :;; esac; }

#============ Disk Usage Helpers ============
capture_disk_usage(){ local var_name=$1; local -n ref="$var_name"; ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}'); }

#============ File Finding Helpers ============
find_files(){ if has fd; then fd -H "$@"; else find "$@"; fi; }
find0(){ local root="$1"; shift; if has fdf; then fdf -H -0 "$@" . "$root"; elif has fd; then fd -H -0 "$@" . "$root"; else find "$root" "$@" -print0; fi; }

#============ Package Manager Detection ============
_PKG_MGR_CACHED=""
_AUR_OPTS_CACHED=()
detect_pkg_manager(){ if [[ -n $_PKG_MGR_CACHED ]]; then printf '%s\n' "$_PKG_MGR_CACHED"; printf '%s\n' "${_AUR_OPTS_CACHED[@]}"; return 0; fi; local pkgmgr; if has paru; then pkgmgr=paru; _AUR_OPTS_CACHED=(--batchinstall --combinedupgrade --nokeepsrc); elif has yay; then pkgmgr=yay; _AUR_OPTS_CACHED=(--answerclean y --answerdiff n --answeredit n --answerupgrade y); else pkgmgr=pacman; _AUR_OPTS_CACHED=(); fi; _PKG_MGR_CACHED=$pkgmgr; printf '%s\n' "$pkgmgr"; printf '%s\n' "${_AUR_OPTS_CACHED[@]}"; }
get_pkg_manager(){ if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi; printf '%s\n' "$_PKG_MGR_CACHED"; }
get_aur_opts(){ if [[ -z $_PKG_MGR_CACHED ]]; then detect_pkg_manager >/dev/null; fi; printf '%s\n' "${_AUR_OPTS_CACHED[@]}"; }

#============ SQLite Maintenance ============
vacuum_sqlite(){ local db=$1 s_old s_new; [[ -f $db ]] || { printf '0\n'; return; }; [[ -f ${db}-wal || -f ${db}-journal ]] && { printf '0\n'; return; }; if ! head -c 16 "$db" 2>/dev/null | grep -q 'SQLite format 3'; then printf '0\n'; return; fi; s_old=$(stat -c%s "$db" 2>/dev/null) || { printf '0\n'; return; }; sqlite3 "$db" 'PRAGMA journal_mode=delete; VACUUM; PRAGMA optimize;' &>/dev/null || { printf '0\n'; return; }; s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old; printf '%d\n' "$((s_old - s_new))"; }
clean_sqlite_dbs(){ local total=0 db saved; while IFS= read -r -d '' db; do [[ -f $db ]] || continue; saved=$(vacuum_sqlite "$db" || printf '0'); ((saved > 0)) && total=$((total + saved)); done < <(find0 . -maxdepth 1 -type f); ((total > 0)) && printf '  %s\n' "${GRN}Vacuumed SQLite DBs, saved $((total / 1024)) KB${DEF}"; }

#============ Process Management ============
ensure_not_running_any(){ local timeout=6 p; local pattern=$(printf '%s|' "$@"); pattern=${pattern%|}; pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return; for p in "$@"; do pgrep -x -u "$USER" "$p" &>/dev/null && printf '  %s\n' "${YLW}Waiting for ${p} to exit...${DEF}"; done; local wait_time=$timeout; while ((wait_time-- > 0)); do pgrep -x -u "$USER" -f "$pattern" &>/dev/null || return; sleep 1; done; if pgrep -x -u "$USER" -f "$pattern" &>/dev/null; then printf '  %s\n' "${RED}Killing remaining processes...${DEF}"; pkill -KILL -x -u "$USER" -f "$pattern" &>/dev/null || :; sleep 1; fi; }

#============ Browser Profile Detection ============
foxdir(){ local base=$1 p; [[ -d $base ]] || return 1; if [[ -f $base/installs.ini ]]; then p=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1;next} f&&/^Default=/{print $2;exit}' "$base/installs.ini"); [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }; fi; if [[ -f $base/profiles.ini ]]; then p=$(awk -F= '/^\[.*\]/{s=0} /^\[Profile[0-9]+\]/{s=1} s&&/^Default=1/{d=1} s&&/^Path=/{if(d){print $2;exit}}' "$base/profiles.ini"); [[ -n $p && -d $base/$p ]] && { printf '%s\n' "$base/$p"; return 0; }; fi; return 1; }
mozilla_profiles(){ local base=$1 p; declare -A seen; [[ -d $base ]] || return 0; if [[ -f $base/installs.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }; done < <(awk -F= '/^Default=/ {print $2}' "$base/installs.ini"); fi; if [[ -f $base/profiles.ini ]]; then while IFS= read -r p; do [[ -d $base/$p && -z ${seen[$p]:-} ]] && { printf '%s\n' "$base/$p"; seen[$p]=1; }; done < <(awk -F= '/^Path=/ {print $2}' "$base/profiles.ini"); fi; }
chrome_roots_for(){ case "$1" in chrome) printf '%s\n' "$HOME/.config/google-chrome" "$HOME/.var/app/com.google.Chrome/config/google-chrome" "$HOME/snap/google-chrome/current/.config/google-chrome" ;; chromium) printf '%s\n' "$HOME/.config/chromium" "$HOME/.var/app/org.chromium.Chromium/config/chromium" "$HOME/snap/chromium/current/.config/chromium" ;; brave) printf '%s\n' "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "$HOME/snap/brave/current/.config/BraveSoftware/Brave-Browser" ;; opera) printf '%s\n' "$HOME/.config/opera" "$HOME/.config/opera-beta" "$HOME/.config/opera-developer" ;; *) : ;; esac; }
chrome_profiles(){ local root=$1 d; for d in "$root"/Default "$root"/"Profile "*; do [[ -d $d ]] && printf '%s\n' "$d"; done; }

#============ Path Cleaning Helpers ============
_expand_wildcards(){ local path=$1; local -n result_ref=$2; if [[ $path == *\** ]]; then shopt -s nullglob; local -a items=($path); for item in "${items[@]}"; do [[ -e $item ]] && result_ref+=("$item"); done; shopt -u nullglob; else [[ -e $path ]] && result_ref+=("$path"); fi; }
clean_paths(){ local paths=("$@") path; local existing_paths=(); for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done; [[ ${#existing_paths[@]} -gt 0 ]] && rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :; }
clean_with_sudo(){ local paths=("$@") path; local existing_paths=(); for path in "${paths[@]}"; do _expand_wildcards "$path" existing_paths; done; [[ ${#existing_paths[@]} -gt 0 ]] && run_priv rm -rf --preserve-root -- "${existing_paths[@]}" &>/dev/null || :; }

#============ Download Tool Detection ============
_DOWNLOAD_TOOL_CACHED=""
get_download_tool(){ local skip_aria2=0; [[ ${1:-} == --no-aria2 ]] && skip_aria2=1; if [[ -n $_DOWNLOAD_TOOL_CACHED && $skip_aria2 -eq 0 ]]; then printf '%s' "$_DOWNLOAD_TOOL_CACHED"; return 0; fi; local tool; if [[ $skip_aria2 -eq 0 ]] && has aria2c; then tool=aria2c; elif has curl; then tool=curl; elif has wget2; then tool=wget2; elif has wget; then tool=wget; else return 1; fi; [[ $skip_aria2 -eq 0 ]] && _DOWNLOAD_TOOL_CACHED=$tool; printf '%s' "$tool"; }
download_file(){ local url=$1 output=$2 tool; tool=$(get_download_tool) || return 1; case $tool in aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "$(dirname "$output")" -o "$(basename "$output")" "$url" ;; curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;; wget2) wget2 -q -O "$output" "$url" ;; wget) wget -qO "$output" "$url" ;; *) return 1 ;; esac; }

cleanup_pacman_lock(){ run_priv rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
# ============ End of inlined lib/common.sh ============

# Override environment for this script
SHELL=/bin/bash
export HOME="/home/${SUDO_USER:-$USER}"

# Initialize privilege and sync
PRIV_CMD=$(init_priv)
sync

# Color overrides for this script (uses different scheme)
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' C='\033[0;36m' Z='\033[0m' D='\033[1m'
MIRRORDIR=/etc/pacman.d
BACKUPDIR=/etc/pacman.d/.bak
LOGFILE=/var/log/mirror-rank.log
COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-$(curl -sf https://ipapi.co/country_code || echo DE)}
CONCURRENCY=$(nproc)
MAX_MIRRORS=10
TIMEOUT=30
TEST_PKG=core/pacman
STATE_FILE=state
VERBOSE=no
ARCH_URL='https://archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on'
REPOS=(cachyos chaotic-aur endeavouros alhp)
REF_LEVEL=""
TMP=()
export RATE_MIRRORS_PROTOCOL=https RATE_MIRRORS_ALLOW_ROOT=true \
  RATE_MIRRORS_DISABLE_COMMENTS_IN_FILE=true RATE_MIRRORS_DISABLE_COMMENTS=true \
  RATE_MIRRORS_ENTRY_COUNTRY="$COUNTRY" CONCURRENCY

log(){ printf "[%s] %s\n" "$1" "${@:2}" | tee -a "$LOGFILE" >&2; }
die(){ log ERROR "$@"; cleanup; exit 1; }
info(){ log INFO "$@"; }
warn(){ log WARN "$@"; }
cleanup(){ ((${#TMP[@]})) && rm -f "${TMP[@]}" &>/dev/null || :; }
trap cleanup EXIT INT TERM

backup(){
  local src=$1 dst=$BACKUPDIR/$(basename "$src")-$(date +%s).bak
  [[ -d $BACKUPDIR ]] || run_priv mkdir -p "$BACKUPDIR"
  run_priv cp -a "$src" "$dst" &>/dev/null || return 1
  # Optimized: Use find with -delete to avoid sort overhead, keep 20 newest
  find "$BACKUPDIR" -name "$(basename "$src")-*.bak" -printf '%T@ %p\n' 2>/dev/null | \
    sort -rn | tail -n+21 | cut -d' ' -f2- | xargs -r run_priv rm -f &>/dev/null || :
}

get_ref(){
  local url=https://mirror.alpix.eu/endeavouros/repo/$STATE_FILE
  REF_LEVEL=$(curl -sf -m10 "$url" 2>/dev/null | head -n1)
  [[ $REF_LEVEL =~ ^[0-9]+$ ]] || REF_LEVEL=""
  [[ $VERBOSE = yes && $REF_LEVEL ]] && info "Ref level: $REF_LEVEL"
}

test_speed(){
  local url=$1${TEST_PKG}
  curl -o /dev/null -sf -w '%{speed_download}' --connect-timeout 5 -m10 "$url" 2>/dev/null | awk '{printf "%.0f",$1}' || echo 0
}

rank_manual(){
  local file=$1 tmp=$(mktemp); TMP+=("$tmp")
  mapfile -t mirs < <(grep -Po '(?<=^Server = ).*' "$file")
  ((${#mirs[@]})) || die "No mirrors in $file"
  
  info "Testing ${#mirs[@]} mirrors (parallel)"
  # Pre-strip path to avoid repeated sed invocations
  local -a urls=()
  for m in "${mirs[@]}"; do
    urls+=("${m%/\$repo/\$arch}")
  done
  
  # Use printf instead of echo in subprocess for better performance
  printf '%s\n' "${urls[@]}" | \
  xargs -P"$CONCURRENCY" -I{} bash -c '
    spd=$(curl -o /dev/null -sf -w "%{speed_download}" --connect-timeout 5 -m10 "{}'"$TEST_PKG"'" 2>/dev/null | awk "{printf \"%.0f\",\$1}" || printf 0)
    printf "%s %s\n" "$spd" "{}"
  ' | awk '$1>0' | sort -rn | head -n"$MAX_MIRRORS" > "$tmp.spd"
  
  {
    printf "## Ranked %s\n\n" "$(date)"
    awk '{print "Server = " $2}' "$tmp.spd"
  } | run_priv tee "$tmp" >/dev/null
  run_priv install -m644 -b -S -T "$tmp" "$file"
}

rank_rate(){
  local name=$1 file=${2:-$MIRRORDIR/${1}-mirrorlist}
  [[ -r $file ]] || { warn "Missing $file"; return 1; }
  local tmp=$(mktemp); TMP+=("$tmp")
  
  backup "$file"
  info "Ranking $name via rate-mirrors"
  
  rate-mirrors stdin \
    --save="$tmp" \
    --fetch-mirrors-timeout=300000 \
    --comment-prefix='# ' \
    --output-prefix='Server = ' \
    --path-to-return='$repo/os/$arch' \
    < <(grep -Eo 'https?://[^ ]+' "$file" | sort -u) 2>/dev/null || {
      warn "rate-mirrors failed for $name, falling back"
      rank_manual "$file"
      return
    }
  run_priv install -m644 -b -S -T "$tmp" "$file"
}

rank_arch_fresh(){
  local url="${1:-$ARCH_URL}" path="$MIRRORDIR/mirrorlist" tmp=$(mktemp); TMP+=("$tmp")
  
  [[ -f $path ]] && backup "$path"
  info "Fetching fresh Arch mirrorlist from archlinux.org"
  
  if has curl; then
    curl -sfL --retry 3 --retry-delay 1 "$url" -o "$tmp.dl" || die "Download failed: $url"
  elif has wget; then
    wget -qO "$tmp.dl" "$url" || die "Download failed: $url"
  else
    die "Neither curl nor wget available"
  fi
  
  local -a urls
  mapfile -t urls < <(awk '/^#?Server/{url=$3; sub(/\$.*/,"",url); if(!seen[url]++)print url}' "$tmp.dl")
  ((${#urls[@]}>0)) || die "No server entries found"
  
  info "Ranking ${#urls[@]} fresh Arch mirrors"
  printf '%s\n' "${urls[@]}" \
    | rate-mirrors --save="$tmp" stdin \
      --path-to-test="extra/os/x86_64/extra.files" \
      --path-to-return="\$repo/os/\$arch" \
      --comment-prefix="# " --output-prefix="Server = " \
  || { warn "rate-mirrors failed for Arch, falling back"; rank_manual "$path"; return; }
  
  run_priv install -m644 -b -S -T "$tmp" "$path"
}

rank_reflector(){
  local file=$1 tmp=$(mktemp); TMP+=("$tmp")
  
  backup "$file"
  info "Ranking via reflector"
  
  local -a args=(--save "$tmp" --protocol https --latest 20 --sort rate -n"$MAX_MIRRORS" --threads "$CONCURRENCY")
  [[ $COUNTRY =~ ^[A-Z]{2}$ ]] && args+=(--country "$COUNTRY")
  
  run_priv reflector "${args[@]}" &>/dev/null || {
    warn "reflector failed, falling back"
    rank_manual "$file"
    return
  }
  run_priv install -m644 -b -S -T "$tmp" "$file"
}

benchmark(){
  local file=${1:-$MIRRORDIR/mirrorlist}
  # Use awk to extract servers in one pass instead of grep+sed
  mapfile -t srvs < <(awk '/^Server/ {print $3}' "$file" | head -n5)
  ((${#srvs[@]})) || die "No servers in $file"
  
  printf "${C}${D}Benchmarking top %d mirrors:${Z}\n\n" ${#srvs[@]}
  for i in "${!srvs[@]}"; do
    local srv=${srvs[$i]} host=${srv#*://}; host=${host%%/*}
    printf "${C}%d: %s${Z}\n" $((i+1)) "$host"
    
    local spd=$(test_speed "$srv")
    if ((spd>0)); then
      # Use bash arithmetic instead of awk for simple division
      printf "  Speed: ${G}%.2f MB/s${Z}\n" "$(awk "BEGIN{print $spd/1048576}")"
    else
      printf "  Speed: ${R}FAIL${Z}\n"
    fi
    
    local png=$(ping -c1 -W2 "$host" 2>/dev/null | awk -F'[= ]' '/time=/{print $(NF-1)}')
    [[ $png ]] && printf "  Ping:  ${G}%s ms${Z}\n" "$png" || printf "  Ping:  ${Y}N/A${Z}\n"
  done
}

restore(){
  [[ -d $BACKUPDIR ]] || die "No backup dir"
  mapfile -t baks < <(find "$BACKUPDIR" -name "*-mirrorlist-*.bak" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  ((${#baks[@]})) || die "No backups found"
  
  printf "${C}Available backups:${Z}\n"
  for i in "${!baks[@]}"; do
    printf "%2d. %s\n" $((i+1)) "$(basename "${baks[$i]}")"
  done
  
  read -rp "Select [1-${#baks[@]}]: " n
  [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#baks[@]} ]] || die "Invalid selection"
  
  local tgt=$(basename "${baks[$((n-1))]}" | sed 's/-[0-9]\+\.bak$//')
  run_priv cp "${baks[$((n-1))]}" "$MIRRORDIR/$tgt" || die "Restore failed"
  info "Restored $tgt"
  run_priv pacman -Sy &>/dev/null || :
}

opt_all(){
  info "Starting optimization (country: $COUNTRY)"
  run_priv pacman -Syyuq --noconfirm --needed || :
  run_priv pacman-db-upgrade --nocolor &>/dev/null || :
  has keyserver-rank && run_priv keyserver-rank --yes &>/dev/null || :
  
  [[ -f /etc/eos-rankmirrors.disabled ]] && source /etc/eos-rankmirrors.disabled || :
  get_ref
  
  if has rate-mirrors; then
    rank_arch_fresh "$ARCH_URL"
    if has cachyos-rate-mirrors; then
      info "Using cachyos-rate-mirrors"
      run_priv cachyos-rate-mirrors || :
    else
      for repo in "${REPOS[@]}"; do
        [[ -f $MIRRORDIR/${repo}-mirrorlist ]] && rank_rate "$repo" || :
      done
    fi
    info "Searching for other mirrorlists..."
    local f repo
    for f in "$MIRRORDIR"/*mirrorlist; do
      [[ -L $f || $f == "$MIRRORDIR/mirrorlist" ]] && continue
      repo=$(basename "$f" "-mirrorlist")
      [[ $repo == "$(basename "$f")" ]] && continue
      [[ " ${REPOS[*]} " =~ " $repo " ]] && continue
      rank_rate "$repo" "$f" || :
    done
  elif has reflector; then
    rank_reflector "$MIRRORDIR/mirrorlist" || :
  else
    info "Using manual ranking"
    [[ -f $MIRRORDIR/mirrorlist ]] && rank_manual "$MIRRORDIR/mirrorlist" || :
    for repo in "${REPOS[@]}"; do
      [[ -f $MIRRORDIR/${repo}-mirrorlist ]] && rank_manual "$MIRRORDIR/${repo}-mirrorlist" || :
    done
  fi
  run_priv chmod 644 "$MIRRORDIR"/*mirrorlist* 2>/dev/null || :
  info "Updated all mirrorlists"
  run_priv pacman -Syyq --noconfirm --needed || :
}

show_current(){
  local file=${1:-$MIRRORDIR/mirrorlist}
  [[ -r $file ]] || die "Cannot read $file"
  printf "${C}Current mirrors in %s:${Z}\n" "$(basename "$file")"
  grep '^Server' "$file" | head -n10 | nl -w2 -s'. ' | sed "s|^|  ${B}|;s|$|${Z}|"
}

menu(){
  while :; do
    printf "\n${C}${D}╔═══════════════════════════════════╗\n"
    printf "║  Mirror Optimizer [%-2s]          ║\n" "$COUNTRY"
    printf "╚═══════════════════════════════════╝${Z}\n\n"
    printf "  ${B}1)${Z} Optimize all mirrors\n"
    printf "  ${B}2)${Z} Benchmark current\n"
    printf "  ${B}3)${Z} Show current mirrorlist\n"
    printf "  ${B}4)${Z} Restore backup\n"
    printf "  ${B}5)${Z} Set country [%s]\n" "$COUNTRY"
    printf "  ${B}6)${Z} Toggle verbose [%s]\n" "$VERBOSE"
    printf "  ${B}7)${Z} Exit\n\n"
    read -rp "${D}>${Z} " c
    
    case $c in
      1) opt_all;;
      2) benchmark;;
      3) show_current;;
      4) restore;;
      5) read -rp "Country code (2-letter): " cc; COUNTRY=${cc^^}; export RATE_MIRRORS_ENTRY_COUNTRY=$COUNTRY;;
      6) [[ $VERBOSE = yes ]] && VERBOSE=no || VERBOSE=yes;;
      7|q|Q) break;;
      *) printf "${R}Invalid choice${Z}\n";;
    esac
    [[ $c =~ ^[1-6]$ ]] && { printf "\n${Y}Press Enter to continue...${Z}"; read -rs; }
  done
}

usage(){
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -o, --optimize        Optimize all mirrors (fetches fresh Arch mirrorlist)
  -b, --benchmark [F]   Benchmark mirrors (default: $MIRRORDIR/mirrorlist)
  -s, --show [F]        Show current mirrorlist
  -r, --restore         Restore from backup
  -c, --country CODE    Set country (2-letter uppercase)
  -t, --timeout SEC     Timeout for tests (default: $TIMEOUT)
  -v, --verbose         Verbose output
  -h, --help            Show this help

Examples:
  $(basename "$0")              # Interactive menu
  $(basename "$0") -o           # Optimize all (with fresh Arch mirrors)
  $(basename "$0") -c US -o     # Optimize for US mirrors
  $(basename "$0") -b           # Benchmark current
EOF
  exit 0
}

main(){
  [[ $EUID -eq 0 || $# -gt 0 ]] || exec "$PRIV_CMD" -E "$0" "$@"
  run_priv mkdir -p "$(dirname "$LOGFILE")" "$BACKUPDIR" &>/dev/null || :
  
  while (($#)); do
    case $1 in
      -o|--optimize) opt_all; exit;;
      -b|--benchmark) benchmark "${2:-}"; exit;;
      -s|--show) show_current "${2:-}"; exit;;
      -r|--restore) restore; exit;;
      -c|--country) COUNTRY=${2^^}; export RATE_MIRRORS_ENTRY_COUNTRY=$COUNTRY; shift;;
      -t|--timeout) TIMEOUT=$2; shift;;
      -v|--verbose) VERBOSE=yes;;
      -h|--help) usage;;
      *) die "Unknown option: $1 (use -h for help)";;
    esac
    shift
  done
  
  menu
}

main "$@"
