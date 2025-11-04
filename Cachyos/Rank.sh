#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'SHELL='/bin/bash'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD" || exit 1
has(){ command -v -- "$1" &>/dev/null; }
sudo -v; sync
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' C='\033[0;36m' Z='\033[0m' D='\033[1m'

MIRRORDIR="/etc/pacman.d"
BACKUPDIR="/etc/pacman.d/.bak"
LOGFILE="/var/log/mirror-rank.log"
COUNTRY=${RATE_MIRRORS_ENTRY_COUNTRY:-$(curl -sf https://ipapi.co/country_code || echo DE)}
CONCURRENCY="$(nproc)"
MAX_MIRRORS=10
TEST_PKG=core/pacman
export RATE_MIRRORS_PROTOCOL=https RATE_MIRRORS_ALLOW_ROOT=true \
    RATE_MIRRORS_DISABLE_COMMENTS_IN_FILE=true RATE_MIRRORS_DISABLE_COMMENTS=true \
    RATE_MIRRORS_ENTRY_COUNTRY=DE CONCURRENCY="$(nproc)"

log(){ local lvl=$1; shift; printf "[%s] %s\n" "$lvl" "$*" | tee -a "$LOGFILE" >&2; }
die(){ log ERROR "$*"; exit 1; }

backup(){
  local src=$1 dst=$BACKUPDIR/$(basename "$src")-$(date +%s).bak
  [[ -d $BACKUPDIR ]] || sudo mkdir -p "$BACKUPDIR"
  sudo cp -a "$src" "$dst"
  local cnt=($(find "$BACKUPDIR" -name "$(basename "$src")-*.bak" -printf '%T@ %p\n' | sort -rn))
  ((${#cnt[@]}>20)) && printf '%s\n' "${cnt[@]:20}" | cut -d' ' -f2- | xargs -r sudo rm -f
}
test_speed(){ local url=$1${TEST_PKG}; curl -o /dev/null -sf -w '%{speed_download}' --connect-timeout 5 -m10 "$url" 2>/dev/null | awk '{printf "%.0f",$1}' || echo 0; }

rank_manual(){
  local file=$1 tmp=$(mktemp)
  declare -A speeds
  local -a mirrors=()
  while IFS= read -r line; do
    [[ $line =~ ^Server[[:space:]]*=[[:space:]]*(.*) ]] && mirrors+=("${BASH_REMATCH[1]}")
  done < "$file"
  ((${#mirrors[@]})) || die "No mirrors in $file"
  log INFO "Testing ${#mirrors[@]} mirrors (parallel)"
  printf '%s\n' "${mirrors[@]}" | xargs -P"$CONCURRENCY" -I{} bash -c 'echo "$(curl -o /dev/null -sf -w "%{speed_download}" --connect-timeout 5 -m10 "{}'"$TEST_PKG"'" 2>/dev/null | awk "{printf \"%.0f\",\$1}" || echo 0) {}"' | \
  while read -r spd mir; do
    ((spd>0)) && speeds["$mir"]=$spd
  done
  {
    printf "## Ranked %s\n\n" "$(date)"
    for m in $(for k in "${!speeds[@]}"; do echo "${speeds[$k]} $k"; done | sort -rn | head -n"$MAX_MIRRORS" | cut -d' ' -f2-); do
      echo "Server = $m"
    done
  } | sudo tee "$tmp" >/dev/null
  sudo install -m644 -b -S -T "$tmp" "$file"
  rm -f "$tmp"
}

rank_rate_mirrors(){
  local name=$1 file=${2:-$MIRRORDIR/${1}-mirrorlist} tmp=$(mktemp)
  [[ -r $file ]] || { log ERROR "Missing $file"; return 1; }
  backup "$file"
  log INFO "Ranking $name via rate-mirrors"
  rate-mirrors stdin \
    --save="$tmp" \
    --fetch-mirrors-timeout=300000 \
    --comment-prefix="# " \
    --output-prefix="Server = " \
    --path-to-return='$repo/os/$arch' \
    < <(grep -Eo 'https?://[^ ]+' "$file" | sort -u) || { rank_manual "$file"; return; }
  sudo install -m644 -b -S -T "$tmp" "$file"
  rm -f "$tmp"
}

rank_reflector(){
  local file=$1 tmp=$(mktemp)
  backup "$file"
  log INFO "Ranking via reflector"
  local -a args=(--save "$tmp" --protocol https --latest 20 --sort rate -n"$MAX_MIRRORS" --threads "$CONCURRENCY")
  [[ $COUNTRY =~ ^[A-Z]{2}$ ]] && args+=(--country "$COUNTRY")
  sudo reflector "${args[@]}" &>/dev/null || { rank_manual "$file"; return; }
  sudo install -m644 -b -S -T "$tmp" "$file"
  rm -f "$tmp"
}
benchmark(){
  local file=${1:-$MIRRORDIR/mirrorlist}
  mapfile -t srvs < <(grep '^Server' "$file" | head -n5 | sed 's/Server = //')
  ((${#srvs[@]})) || die "No servers in $file"
  for i in "${!srvs[@]}"; do
    local srv=${srvs[$i]} host=$(sed 's|.*://||;s|/.*||' <<<"$srv")
    printf "${C}%d: %s${Z}\n" $((i+1)) "$host"
    local spd=$(test_speed "$srv")
    ((spd>0)) && printf "  Speed: ${G}%.2f MB/s${Z}\n" "$(awk "BEGIN{print $spd/1048576}")" || printf "  Speed: ${R}FAIL${Z}\n"
    local ping=$(ping -c1 -W2 "$host" 2>/dev/null | awk -F'[= ]' '/time=/{print $(NF-1)}' || :)
    [[ -n $ping ]] && printf "  Ping:  ${G}%s ms${Z}\n" "$ping" || printf "  Ping:  ${Y}N/A${Z}\n"
  done
}
restore(){
  [[ -d $BACKUPDIR ]] || die "No backup dir"
  mapfile -t baks < <(find "$BACKUPDIR" -name "*-mirrorlist-*.bak" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
  ((${#baks[@]})) || die "No backups"
  for i in "${!baks[@]}"; do
    printf "%d. %s\n" $((i+1)) "$(basename "${baks[$i]}")"
  done
  read -rp "Select [1-${#baks[@]}]: " n
  [[ $n =~ ^[0-9]+$ && $n -ge 1 && $n -le ${#baks[@]} ]] || die "Invalid"
  local tgt=$(sed 's/-[0-9]\+\.bak$//' <<<"$(basename "${baks[$((n-1))]}")")
  sudo cp "${baks[$((n-1))]}" "$MIRRORDIR/$tgt"
  log INFO "Restored $tgt"
}
opt_all(){
  sudo pacman -Syyuq --noconfirm --needed || :
  sudo pacman-db-upgrade --nocolor &>/dev/null || :
  has keyserver-rank && sudo keyserver-rank --yes || :
  if has cachyos-rate-mirrors; then
    sudo cachyos-rate-mirrors || :
  elif has rate-mirrors; then
    for repo in arch cachyos chaotic-aur endeavouros alhp; do
      [[ -f $MIRRORDIR/${repo}-mirrorlist ]] && rank_rate_mirrors "$repo" || :
    done
  elif has reflector; then
    [[ -f $MIRRORDIR/mirrorlist ]] && rank_reflector "$MIRRORDIR/mirrorlist"
  else
    [[ -f $MIRRORDIR/mirrorlist ]] && rank_manual "$MIRRORDIR/mirrorlist"
  fi
  sudo chmod go+r "$MIRRORDIR"/*mirrorlist* 2>/dev/null || :
  log INFO "Updated all mirrorlists"
  sudo pacman -Syyq --noconfirm --needed || :
}

show_menu(){
  while :; do
    printf "${C}${D}\n╔════════════════════════════════╗\n║  Mirror Optimizer [%s]     ║\n╚════════════════════════════════╝${Z}\n" "$COUNTRY"
    printf "1) Optimize all\n2) Benchmark current\n3) Restore backup\n4) Set country\n5) Exit\n> "
    read -r c
    case $c in
      1) opt_all;;
      2) benchmark;;
      3) restore;;
      4) read -rp "Country code: " COUNTRY;;
      5) break;;
      *) printf "${R}Invalid${Z}\n";;
    esac
    read -rp "Press Enter..."
  done
}

main(){
  [[ $EUID -eq 0 || $# -gt 0 ]] || exec sudo "$0" "$@"
  sudo mkdir -p "$(dirname "$LOGFILE")" "$BACKUPDIR"
  case ${1:-} in
    -o|--optimize) opt_all;;
    -b|--benchmark) benchmark "${2:-}";;
    -r|--restore) restore;;
    -c|--country) COUNTRY=${2:-$COUNTRY} opt_all;;
    -h|--help) printf "Usage: %s [-o|-b|-r|-c CODE|-h]\n" "$0"; exit;;
    "") show_menu;;
    *) die "Unknown: $1";;
  esac
}

main "$@"
