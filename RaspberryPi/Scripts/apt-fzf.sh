#!/usr/bin/env bash
# apt-parus — sk-preferred frontend for apt/nala/apt-fast
# Replaces du/awk with pure-bash byte-to-human routine.
# Preview cache at ${XDG_CACHE_HOME:-$HOME/.cache}/apt-parus
# TTL via APT_PARUS_CACHE_TTL (default 86400)
# Install: --install
# Style: [[ ... ]], 2-space indentation, use &>/dev/null || :

set -euo pipefail
shopt -s nullglob globstar

export LC_ALL=C LANG=C
: "${SHELL:=/bin/bash}"
: "${XDG_CACHE_HOME:=${HOME:-$HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME%/}/apt-parus"
mkdir -p "$CACHE_DIR"
: "${APT_PARUS_CACHE_TTL:=86400}"
: "${APT_PARUS_CACHE_MAX_BYTES:=0}"

# prefer skim/sk over fzf
if command -v sk &>/dev/null || :; then
  FINDER=sk
elif command -v fzf &>/dev/null || :; then
  FINDER=fzf
else
  echo "Please install skim (sk) or fzf." >&2
  exit 1
fi

# managers
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :
PRIMARY_MANAGER=apt
[[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER=nala
[[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER=apt-fast

# -------------------------
# Pure-bash byte utilities (replaces du/awk)
# -------------------------
total_bytes_in_dir() {
  # Sum sizes of regular files in directory (non-recursive)
  local dir="$1"
  local total=0
  local f s
  while IFS= read -r -d '' f; do
    s=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
    total=$(( total + s ))
  done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null)
  printf '%d' "$total"
}

byte_to_human() {
  # Convert integer bytes -> human with one decimal when needed (B K M G T)
  local bytes=$1
  local -a units=(B K M G T)
  local i=0 pow=1
  # Determine power 1024^i such that bytes < pow*1024 or i==4
  while [[ $bytes -ge $(( pow * 1024 )) && $i -lt 4 ]]; do
    pow=$(( pow * 1024 ))
    i=$(( i + 1 ))
  done
  # scaled value *10 with rounding
  local value10=$(( (bytes * 10 + (pow / 2)) / pow ))
  local whole=$(( value10 / 10 ))
  local dec=$(( value10 % 10 ))
  if [[ $dec -gt 0 ]]; then
    printf '%d.%d%s' "$whole" "$dec" "${units[i]}"
  else
    printf '%d%s' "$whole" "${units[i]}"
  fi
}

# -------------------------
# Cache helpers (use pure-bash total_bytes_in_dir)
# -------------------------
_cache_file_for() {
  local pkg="$1"
  printf '%s/%s.cache' "$CACHE_DIR" "${pkg//[^a-zA-Z0-9._+-]/_}"
}
_cache_mins() { printf '%d' $(( (APT_PARUS_CACHE_TTL + 59) / 60 )); }

evict_old_cache() {
  local mmin; mmin="$(_cache_mins)"
  find "$CACHE_DIR" -maxdepth 1 -type f -mmin +"$mmin" -delete &>/dev/null || :
  if [[ ${APT_PARUS_CACHE_MAX_BYTES:-0} -gt 0 ]]; then
    local total; total=$(total_bytes_in_dir "$CACHE_DIR")
    if [[ $total -gt $APT_PARUS_CACHE_MAX_BYTES ]]; then
      # delete oldest files until under cap
      while IFS= read -r -d '' entry; do
        local file="${entry#* }"
        rm -f "$file" &>/dev/null || :
        total=$(total_bytes_in_dir "$CACHE_DIR")
        [[ $total -le $APT_PARUS_CACHE_MAX_BYTES ]] && break
      done < <(find "$CACHE_DIR" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | tr '\0' '\n' | sort -n | sed -n '1,100p' | tr '\n' '\0')
    fi
  fi
}

_cache_stats() {
  local files size oldest age
  files=$(find "$CACHE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
  size=$(total_bytes_in_dir "$CACHE_DIR")
  oldest=$(find "$CACHE_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -n1 | awk '{print $1}')
  if [[ -z $oldest ]]; then
    age="0m"
  else
    age=$(( ( $(date +%s) - ${oldest%%.*} ) / 60 ))m
  fi
  printf '%s|%s|%s' "$files" "$size" "$age"
}

# -------------------------
# Preview (atomic)
# -------------------------
_generate_preview() {
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="${out}.$$.$RANDOM.tmp"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    printf '\n--- changelog (first 200 lines) ---\n'
    command -v apt-get &>/dev/null && apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
  } >"$tmp" 2>/dev/null || :
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" &>/dev/null || :
  mv -f "$tmp" "$out"
  chmod 644 "$out" &>/dev/null || :
}

_cached_preview_print() {
  local pkg="$1" f
  evict_old_cache
  f="$(_cache_file_for "$pkg")"
  if [[ -f $f && $(( $(date +%s) - $(stat -c %Y -- "$f") )) -lt $APT_PARUS_CACHE_TTL ]]; then
    cat "$f"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print

# -------------------------
# Manager runner (apt-get for apt)
# -------------------------
run_mgr() {
  local action="$1"; shift || :
  local pkgs=("$@"); local cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in
        update) cmd=(nala update) ;;
        upgrade) cmd=(nala upgrade -y) ;;
        autoremove) cmd=(nala autoremove -y) ;;
        clean) cmd=(nala clean) ;;
        *) cmd=(nala "$action" -y "${pkgs[@]}") ;;
      esac ;;
    apt-fast)
      case "$action" in
        update) cmd=(apt-fast update) ;;
        upgrade) cmd=(apt-fast upgrade -y) ;;
        autoremove) cmd=(apt-fast autoremove -y) ;;
        clean) cmd=(apt-fast clean) ;;
        *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;;
      esac ;;
    *)
      case "$action" in
        update) cmd=(apt-get update) ;;
        upgrade) cmd=(apt-get upgrade -y) ;;
        install) cmd=(apt-get install -y "${pkgs[@]}") ;;
        remove) cmd=(apt-get remove -y "${pkgs[@]}") ;;
        purge) cmd=(apt-get purge -y "${pkgs[@]}") ;;
        autoremove) cmd=(apt-get autoremove -y) ;;
        clean) cmd=(apt-get clean) ;;
        *) cmd=(apt "$action" "${pkgs[@]}") ;;
      esac ;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  sudo "${cmd[@]}"
}

choose_manager() {
  local opts=("apt"); [[ $HAS_NALA -eq 1 ]] && opts+=("nala"); [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  local choice; choice=$(printf '%s\n' "${opts[@]}" | $FINDER --height=12% --reverse --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# -------------------------
# Lists, helpers, UI
# -------------------------
list_all_packages() { apt-cache search . 2>/dev/null | sed -E 's/ - /|/; s/\t/ /g'; }
list_installed()     { dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null || :; }
list_upgradable()    { apt list --upgradable 2>/dev/null | awk -F'/' 'NR>1{print $1}'; }
backup_installed()   { local out="${1:-pkglist-$(date +%F).txt}"; dpkg-query -W -f='${binary:Package}\n' | sort -u >"$out"; printf 'Saved: %s\n' "$out"; }
restore_from_file()  {
  local file="$1"; [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  mapfile -t pkgs < <(sed '/^$/d' "$file"); [[ ${#pkgs[@]} -eq 0 ]] && { echo "No packages."; return 0; }
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | $FINDER --multi --height=40% --reverse --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return; run_mgr install "${sel[@]}"
}
show_changelog() { local pkg="$1"; command -v apt-get &>/dev/null && (apt-get changelog "$pkg" 2>/dev/null || echo "No changelog for $pkg") || echo "apt-get unavailable"; }

# -------------------------
# UI / actions
# -------------------------
action_menu_for_pkgs() {
  local pkgs=("$@"); local actions=("Install" "Remove" "Purge" "Changelog" "Cancel")
  local act; act=$(printf '%s\n' "${actions[@]}" | $FINDER --height=12% --reverse --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $act ]] && return
  case "$act" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mg_
