#!/usr/bin/env bash
#
# DESCRIPTION: Raspberry Pi system minimization & optimization suite
#              Aggressive cleanup, ZRAM setup, SWAP mgmt, package purge
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C DEBIAN_FRONTEND=noninteractive

# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# Helpers
has(){ command -v -- "$1" &>/dev/null; }
log(){ printf '%b\n' "${GRN}▶${DEF} $*"; }
warn(){ printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err(){ printf '%b\n' "${RED}✗${DEF} $*" >&2; }
die(){ err "$1"; exit "${2:-1}"; }

# Privilege

# Config
declare -A cfg=([dry_run]=0 [interactive]=1 [aggressive]=0 [disk_before]=0 [disk_after]=0)
run(){ (( cfg[dry_run] )) && log "[DRY] $*" || "$@"; }

# Disk usage tracking
track_disk(){
  local label=$1
  local usage
  usage=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
  log "${BLD}${label}:${DEF} ${usage}"
  [[ $label == "Before" ]] && cfg[disk_before]=$usage || cfg[disk_after]=$usage
}

# Interactive prompt
ask(){
  (( cfg[interactive] == 0 )) && return 0
  local prompt=$1 default=${2:-n}
  local reply
  read -rp "${LBLU}?${DEF} ${prompt} [${default}] " reply
  reply=${reply:-$default}
  [[ $reply =~ ^[Yy] ]]
}

usage(){
  cat <<'EOF'
pi-minify.sh - Raspberry Pi system minimization & cleanup

Usage: pi-minify.sh [OPTIONS]

Options:
  -y, --yes          Non-interactive mode (assumes yes)
  -d, --dry-run      Show actions without executing
  -a, --aggressive   Enable aggressive cleanup (X11, dev pkgs, kernels)
  -h, --help         Show this help

Operations:
  • dpkg nodoc configuration + doc/man/locale purge
  • APT cache cleanup + orphan removal
  • Old kernel purge (keeps current)
  • Optional: SWAP→ZRAM migration
  • Optional: X11/dev package removal
  • Log/cache/history cleanup
  • fstab optimization (noatime, nodiratime)
  • systemd timeout tuning

CAUTION: Aggressive mode removes X11, -dev packages, and non-current kernels
EOF
}

parse_args(){
  while (($#)); do
    case "$1" in
      -y|--yes) cfg[interactive]=0;;
      -d|--dry-run) cfg[dry_run]=1;;
      -a|--aggressive) cfg[aggressive]=1;;
      -h|--help) usage; exit 0;;
      --) shift; break;;
      -*) usage; die "invalid option: $1";;
      *) break;;
    esac
    shift
  done
}

# ────────────────────────────────────────────────────────────
# dpkg & Documentation
# ────────────────────────────────────────────────────────────
configure_dpkg_nodoc(){
  log "Configuring dpkg to exclude docs/man/locales"
  
  sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc >/dev/null <<'EOF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/help/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-include /usr/share/doc/*/copyright
EOF
}

purge_docs(){
  log "Purging documentation, man pages, locales (keep en_GB)"
  
  run find /usr/share/doc/ -depth -type f ! -name copyright -delete 2>/dev/null || :
  run find /usr/share/doc/ -name '*.gz' -o -name '*.pdf' -o -name '*.tex' -delete 2>/dev/null || :
  run find /usr/share/doc/ -type d -empty -delete 2>/dev/null || :
  sudo rm -rf /usr/share/{groff,info,lintian,linda,man}/* /var/cache/man/* 2>/dev/null || :
  
  # Keep only en_GB locale (fallback to en_US if en_GB absent)
  local keep_locale=en_GB
  [[ ! -d /usr/share/locale/en_GB ]] && keep_locale=en_US
  sudo bash -c "cd /usr/share/locale && ls | grep -v ${keep_locale} | xargs rm -rf" 2>/dev/null || :
  sudo bash -c "cd /usr/share/X11/locale && ls | grep -v ${keep_locale} | xargs rm -rf" 2>/dev/null || :
}

# ────────────────────────────────────────────────────────────
# Package Cleanup
# ────────────────────────────────────────────────────────────
purge_packages(){
  log "Removing doc packages, localepurge install"
  
  # localepurge for future locale cleaning
  if ! has localepurge; then
    sudo apt-get install -y localepurge
    run localepurge
  fi
  
  # Doc packages
  local doc_pkgs
  mapfile -t doc_pkgs < <(dpkg --list | awk '/-doc$/ {print $2}')
  (( ${#doc_pkgs[@]} > 0 )) && sudo apt-get purge -y "${doc_pkgs[@]}" || :
  
  # Texlive (large doc suite)
  sudo apt-get purge -y '*texlive*' 2>/dev/null || :
  
  # Old kernels (keep current)
  local current_kernel
  current_kernel=$(uname -r)
  local old_kernels
  mapfile -t old_kernels < <(dpkg --list | awk '{print $2}' | grep 'linux-image-.*-generic' | grep -v "$current_kernel")
  (( ${#old_kernels[@]} > 0 )) && {
    log "Purging old kernels (keeping ${current_kernel})"
    sudo apt-get purge -y "${old_kernels[@]}"
  }
  
  # Orphaned config packages
  local orphaned
  mapfile -t orphaned < <(dpkg -l | awk '/^rc/ {print $2}')
  (( ${#orphaned[@]} > 0 )) && sudo apt-get purge -y "${orphaned[@]}" || :
}

purge_aggressive(){
  (( cfg[aggressive] == 0 )) && return 0
  
  warn "Aggressive mode: removing X11, dev packages, extras"
  
  # X11 libraries
  sudo apt-get purge -y libx11-data xauth libxmuu1 libxcb1 libx11-6 libxext6 2>/dev/null || :
  
  # Dev packages (commented by default - uncomment if needed)
  # local dev_pkgs
  # mapfile -t dev_pkgs < <(dpkg --list | awk '/-dev$/ {print $2}')
  # (( ${#dev_pkgs[@]} > 0 )) && sudo apt-get purge -y "${dev_pkgs[@]}" || :
  
  # Miscellaneous bloat
  sudo apt-get purge -y popularity-contest installation-report \
    wireless-tools wpasupplicant libraspberrypi-doc snapd 'cups*' 2>/dev/null || :
}

cleanup_apt(){
  log "APT cleanup: cache, orphans, deborphan"
  
  has deborphan || sudo apt-get install -y deborphan
  
  sudo apt-get autoremove --purge -y
  sudo apt-get autoclean -y
  sudo apt-get clean -y
  
  # Deborphan recursive orphan removal
  local orphans
  while mapfile -t orphans < <(deborphan) && (( ${#orphans[@]} > 0 )); do
    sudo apt-get purge -y "${orphans[@]}"
  done
}

# ────────────────────────────────────────────────────────────
# Cache & Temp Cleanup
# ────────────────────────────────────────────────────────────
clean_caches(){
  log "Cleaning caches, temp files, history"
  
  # System caches
  sudo rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/* 2>/dev/null || :
  
  # User caches
  run rm -rf ~/.cache/* ~/.thumbnails/* ~/.cache/thumbnails/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
  
  # History files
  unset HISTFILE
  run rm -f ~/.{bash,python}_history 2>/dev/null || :
  sudo rm -f /root/.{bash,python}_history 2>/dev/null || :
  
  # Log truncation
  while IFS= read -r logfile; do
    echo -ne '' | sudo tee "$logfile" >/dev/null
  done < <(find /var/log -type f)
}

# ────────────────────────────────────────────────────────────
# ZRAM Setup
# ────────────────────────────────────────────────────────────
disable_swap(){
  log "Disabling SWAP partition"
  
  has dphys-swapfile && {
    sudo dphys-swapfile swapoff
    sudo dphys-swapfile uninstall
    sudo update-rc.d dphys-swapfile remove
  }
  sudo swapoff -a
}

enable_zram(){
  log "Enabling ZRAM (compressed swap in RAM)"
  
  sudo tee /usr/local/bin/zram-init >/dev/null <<'ZRAMSCRIPT'
#!/usr/bin/env bash
set -euo pipefail

CORES=$(nproc --all)
ZRAM_SIZE_MB=${ZRAM_SIZE_MB:-2048}

modprobe zram num_devices="${CORES}"
swapoff -a 2>/dev/null || :

SIZE=$(( ($(awk '/^MemTotal:/ {print $2}' /proc/meminfo) / CORES) * 1024 ))
[[ ${ZRAM_SIZE_MB} -gt 0 ]] && SIZE=$(( ZRAM_SIZE_MB * 1024 * 1024 / CORES ))

for ((CORE=0; CORE<CORES; CORE++)); do
  echo "${SIZE}" > /sys/block/zram${CORE}/disksize
  mkswap /dev/zram${CORE} &>/dev/null
  swapon -p 5 /dev/zram${CORE}
done

echo 1 > /sys/kernel/mm/ksm/run
ZRAMSCRIPT

  sudo chmod +x /usr/local/bin/zram-init
  sudo /usr/local/bin/zram-init
  
  # Persist via systemd service
  sudo tee /etc/systemd/system/zram-init.service >/dev/null <<'EOF'
[Unit]
Description=ZRAM compressed swap initialization
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zram-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable zram-init.service
}

# ────────────────────────────────────────────────────────────
# System Tweaks
# ────────────────────────────────────────────────────────────
optimize_fstab(){
  log "Optimizing fstab: noatime, nodiratime"
  
  sudo sed -i 's/\(defaults\)/\1,noatime,nodiratime/' /etc/fstab
}

optimize_systemd(){
  log "Reducing systemd stop timeout: 90s→5s"
  
  sudo sed -i 's/#DefaultTimeoutStopSec=90s/DefaultTimeoutStopSec=5s/' /etc/systemd/system.conf
}

disable_extra_ttys(){
  [[ ! -f /etc/inittab ]] && return 0
  
  log "Disabling extra TTYs (2-6) for RAM savings"
  sudo sed -i '/[2-6]:23:respawn:\/sbin\/getty 38400 tty[2-6]/s/^/#/' /etc/inittab
}

# ────────────────────────────────────────────────────────────
# Main Orchestration
# ────────────────────────────────────────────────────────────
main(){
  parse_args "$@"
  
  log "${BLD}Raspberry Pi System Minification${DEF}"
  log "Mode: $([[ ${cfg[dry_run]} -eq 1 ]] && echo 'DRY-RUN' || echo 'LIVE')"
  log "Interactive: $([[ ${cfg[interactive]} -eq 1 ]] && echo 'YES' || echo 'NO')"
  log "Aggressive: $([[ ${cfg[aggressive]} -eq 1 ]] && echo 'YES' || echo 'NO')"
  
  track_disk "Before"
  
  # Core cleanup (always)
  configure_dpkg_nodoc
  purge_docs
  purge_packages
  cleanup_apt
  clean_caches
  
  # Aggressive cleanup (conditional)
  [[ ${cfg[aggressive]} -eq 1 ]] && purge_aggressive
  
  # ZRAM setup (interactive or forced)
  if ask "Disable SWAP and enable ZRAM?" y; then
    disable_swap
    enable_zram
  fi
  
  # System tweaks (interactive)
  ask "Optimize fstab (noatime, nodiratime)?" y && optimize_fstab
  ask "Reduce systemd stop timeout to 5s?" y && optimize_systemd
  ask "Disable extra TTYs (2-6) for RAM savings?" n && disable_extra_ttys
  
  track_disk "After"
  
  log "${GRN}✓${DEF} Minification complete"
  log "Disk before: ${cfg[disk_before]}"
  log "Disk after:  ${cfg[disk_after]}"
  warn "Reboot recommended to fully apply changes"
}

main "$@"
