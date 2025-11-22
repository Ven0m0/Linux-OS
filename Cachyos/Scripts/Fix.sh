#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
download_file(){ local url=$1 output=$2 tool; tool=$(get_download_tool) || return 1; case $tool in aria2c) aria2c -q --max-tries=3 --retry-wait=1 -d "$(dirname "$output")" -o "$(basename "$output")" "$url" ;; curl) curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output" ;; wget2) wget2 -q -O "$output" "$url" ;; wget) wget -qO "$output" "$url" ;; *) return 1 ;; esac; }
cleanup_pacman_lock(){ run_priv rm -f /var/lib/pacman/db.lck &>/dev/null || :; }
# ============ End of inlined lib/common.sh ============



# https://github.com/ekahPruthvi/cynageOS
# https://wiki.cachyos.org/cachyos_basic/faq/

# Initialize privilege tool
PRIV_CMD=$(init_priv)

update() {
  cleanup_pacman_lock
  run_priv pacman -Syu --noconfirm
  has paru && {
    paru -Sua --noconfirm
    paru -Syu --noconfirm
  }
  has yay && {
    yay -Sua --noconfirm
    yay -Syu --noconfirm
  }
}

mirrorfix() {
  log "Fix mirrors"
  has cachyos-rate-mirrors && run_priv cachyos-rate-mirrors
}

cache() {
  run_priv rm -r /var/cache/pacman/pkg/*
  run_priv pacman -Sccq --noconfirm
  has paru && paru -Sccq --noconfirm
  has yay && yay -Sccq --noconfirm
}

log "Fix SSH/GPG permissions"
run_priv chmod -R 700 ~/.{ssh,gnupg}

log "Fix keyrings"
run_priv rm -rf /etc/pacman.d/gnupg/ /var/lib/pacman/sync
run_priv pacman -Sy archlinux-keyring --noconfirm
run_priv pacman-key --init
run_priv pacman-key --populate
run_priv pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
run_priv pacman-key --lsign-key F3B607488DB35A47
run_priv pacman-key --lsign cachyos
run_priv pacman-key --refresh-keys

log "Fix base-devel"
run_priv pacman -Sy --needed base-devel --noconfirm

log "Import wlogout GPG key"
download_file https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F /tmp/wlogout.asc && \
  gpg --import /tmp/wlogout.asc && rm /tmp/wlogout.asc || \
  curl -sS https://keys.openpgp.org/vks/v1/by-fingerprint/F4FDB18A9937358364B276E9E25D679AF73C6D2F | gpg --import -

run_priv pacman -Syyu --noconfirm
