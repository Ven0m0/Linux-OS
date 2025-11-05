#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t'; SHELL=/bin/bash
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" &>/dev/null || :
has(){ command -v -- "$1" &>/dev/null; }
sudo -v; sync

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
  [[ -d $BACKUPDIR ]] || sudo mkdir -p "$BACKUPDIR"
  sudo cp -a "$src" "$dst" &>/dev/null || return 1
  mapfile -t old < <(find "$BACKUPDIR" -name "$(basename "$src")-*.bak" -printf '%T@ %p\n' | sort -rn | tail -n+21 | cut -d' ' -f2-)
  ((${#old[@]})) && printf '%s\n' "${old[@]}" | xargs -r sudo rm -f &>/dev/null || :
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
  printf '%s\n' "${mirs[@]}" | sed 's|/\$repo/\$arch$||' | \
  xargs -P"$CONCURRENCY" -I{} bash -c '
    spd=$(curl -o /dev/null -sf -w "%{speed_download}" --connect-timeout 5 -m10 "{}'"$TEST_PKG"'" 2>/dev/null | awk "{printf \"%.0f\",\$1}" || echo 0)
    echo "$spd {}"
  ' | awk '$1>0{print $0}' | sort -rn | head -n"$MAX_MIRRORS" > "$tmp.spd"
  
  {
    printf "## Ranked %s\n\n" "$(date)"
    awk '{print "Server = " $2}' "$tmp.spd"
  } | sudo tee "$tmp" >/dev/null
  sudo install -m644 -b -S -T "$tmp" "$file"
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
  sudo install -m644 -b -S -T "$tmp" "$file"
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
  
  sudo install -m644 -b -S -T "$tmp" "$path"
}

rank_reflector(){
  local file=$1 tmp=$(mktemp); TMP+=("$tmp")
  
  backup "$file"
  info "Ranking via reflector"
  
  local -a args=(--save "$tmp" --protocol https --latest 20 --sort rate -n"$MAX_MIRRORS" --threads "$CONCURRENCY")
  [[ $COUNTRY =~ ^[A-Z]{2}$ ]] && args+=(--country "$COUNTRY")
  
  sudo reflector "${args[@]}" &>/dev/null || {
    warn "reflector failed, falling back"
    rank_manual "$file"
    return
  }
  sudo install -m644 -b -S -T "$tmp" "$file"
}

benchmark(){
  local file=${1:-$MIRRORDIR/mirrorlist}
  mapfile -t srvs < <(grep '^Server' "$file" | head -n5 | sed 's/Server = //')
  ((${#srvs[@]})) || die "No servers in $file"
  
  printf "${C}${D}Benchmarking top %d mirrors:${Z}\n\n" ${#srvs[@]}
  for i in "${!srvs[@]}"; do
    local srv=${srvs[$i]} host=${srv#*://}; host=${host%%/*}
    printf "${C}%d: %s${Z}\n" $((i+1)) "$host"
    
    local spd=$(test_speed "$srv")
    if ((spd>0)); then
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
  sudo cp "${baks[$((n-1))]}" "$MIRRORDIR/$tgt" || die "Restore failed"
  info "Restored $tgt"
  sudo pacman -Sy &>/dev/null || :
}

opt_all(){
  info "Starting optimization (country: $COUNTRY)"
  sudo pacman -Syyuq --noconfirm --needed || :
  sudo pacman-db-upgrade --nocolor &>/dev/null || :
  has keyserver-rank && sudo keyserver-rank --yes &>/dev/null || :
  
  [[ -f /etc/eos-rankmirrors.disabled ]] && source /etc/eos-rankmirrors.disabled || :
  get_ref
  
  if has rate-mirrors; then
    rank_arch_fresh "$ARCH_URL"
    if has cachyos-rate-mirrors; then
      info "Using cachyos-rate-mirrors"
      sudo cachyos-rate-mirrors || :
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
  sudo chmod 644 "$MIRRORDIR"/*mirrorlist* 2>/dev/null || :
  info "Updated all mirrorlists"
  sudo pacman -Syyq --noconfirm --needed || :
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
  [[ $EUID -eq 0 || $# -gt 0 ]] || exec sudo -E "$0" "$@"
  sudo mkdir -p "$(dirname "$LOGFILE")" "$BACKUPDIR" &>/dev/null || :
  
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
