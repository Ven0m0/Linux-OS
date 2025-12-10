#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
# DESCRIPTION: System fixes for Raspberry Pi - time sync, SSH permissions, Nextcloud
#              Targets: Debian/Raspbian, DietPi
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# Colors
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Core helpers
has(){ command -v -- "$1" &>/dev/null; }
xecho(){ printf '%b\n' "$*"; }
log(){ xecho "${GRN}▶${DEF} $*"; }
warn(){ xecho "${YLW}⚠${DEF} $*">&2; }
err(){ xecho "${RED}✗${DEF} $*">&2; }
die(){
  err "$1"
  exit "${2:-1}"
}
# Find files/directories with fd/fdfind/find fallback
find_with_fallback(){
  local ftype="${1:--f}" pattern="${2:-*}" search_path="${3:-.}" action="${4:-}"
  shift 4 2>/dev/null || shift $#
  if has fd; then
    fd -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"
  elif has fdfind; then
    fdfind -H -t "$ftype" "$pattern" "$search_path" "${action:+"$action"}" "$@"
  else
    local find_type_arg
    case "$ftype" in
      f) find_type_arg="-type f" ;;
      d) find_type_arg="-type d" ;;
      l) find_type_arg="-type l" ;;
      *) find_type_arg="-type f" ;;
    esac
    if [[ -n $action ]]; then
      find "$search_path" "$find_type_arg" -name "$pattern" "$action" "$@"
    else
      find "$search_path" "$find_type_arg" -name "$pattern"
    fi
  fi
}

usage(){
  cat <<'EOF'
Fix.sh - System fixes for Raspberry Pi
Usage: Fix.sh [OPTIONS]
Options:
  -h, --help    Show this help
Performs:
  • Time sync (ntpdate)
  • CA certificates installation
  • SSH permissions fix
  • GnuPG permissions fix
  • Nextcloud container permissions (if exists)
EOF
}

# Parse arguments
parse_args(){
  while (($#)); do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        die "invalid option: $1"
        ;;
      *) break ;;
    esac
    shift
  done
}

# Time synchronization
fix_time_sync(){
  log "Fixing time synchronization"
  if ! dpkg -l | grep -q ntpdate; then
    sudo apt-get update -qq
    sudo apt-get install -y ntpdate || warn "Failed to install ntpdate"
  fi
  if has ntpdate; then
    sudo ntpdate -u ntp.ubuntu.com || warn "Failed to sync time with ntp.ubuntu.com"
  fi
}

# CA certificates
fix_ca_certificates(){
  log "Ensuring CA certificates are installed"
  if ! dpkg -l | grep -q ca-certificates; then
    sudo apt-get update -qq
    sudo apt-get install -y ca-certificates || warn "Failed to install ca-certificates"
  else
    log "CA certificates already installed"
  fi
}

# SSH permissions
fix_ssh_permissions(){
  log "Fixing SSH permissions"
  if [[ -d ~/.ssh ]]; then
    find_with_fallback f "*" ~/.ssh/ -exec chmod 600 {} +
    find_with_fallback d "*" ~/.ssh/ -exec chmod 700 {} +
    find_with_fallback f "*.pub" ~/.ssh/ -exec chmod 644 {} +
    chmod 700 ~/.ssh
    log "SSH permissions fixed"
  else
    warn "~/.ssh directory not found, skipping"
  fi
}

# GnuPG permissions
fix_gnupg_permissions(){
  log "Fixing GnuPG permissions"
  if [[ -d ~/.gnupg ]]; then
    chmod 700 ~/.gnupg
    log "GnuPG permissions fixed"
  else
    warn "~/.gnupg directory not found, skipping"
  fi
}

# Nextcloud container fix
fix_nextcloud(){
  log "Checking for Nextcloud container"
  if ! has docker; then
    warn "Docker not found, skipping Nextcloud fix"
    return 0
  fi

  if ! sudo docker ps --format '{{.Names}}' | grep -q '^nextcloud$'; then
    warn "Nextcloud container not running, skipping"
    return 0
  fi

  log "Fixing Nextcloud /tmp permissions"
  if sudo docker exec nextcloud ls -ld /tmp &>/dev/null; then
    sudo docker exec nextcloud chown -R www-data:www-data /tmp || warn "Failed to chown /tmp in nextcloud"
    sudo docker exec nextcloud chmod -R 755 /tmp || warn "Failed to chmod /tmp in nextcloud"
    log "Nextcloud permissions fixed"
  else
    warn "Failed to access /tmp in nextcloud container"
  fi
}

# Main execution
main(){
  parse_args "$@"
  log "${BLD}Raspberry Pi System Fixes${DEF}"

  fix_time_sync
  fix_ca_certificates
  fix_ssh_permissions
  fix_gnupg_permissions
  fix_nextcloud

  log "${GRN}✓${DEF} All fixes complete"
}

main "$@"
