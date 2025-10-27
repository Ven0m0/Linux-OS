#!/usr/bin/env bash
# apt-fuzz — compact skim/fzf TUI for apt / nala / apt-fast
# Fast interactive package browser for Debian/Ubuntu that:
#   - uses skim (sk) (preferred) or fzf as fuzzy UI
#   - supports apt, nala, apt-fast (auto-detect + choose)
#   - shows fast cached previews of `apt-cache show` + `apt-get changelog`
#   - supports multi-select batch install/remove/purge
#   - backup/restore installed package lists
#   - update/upgrade/clean/autoremove using chosen manager
#   - lightweight cache eviction and a small TUI status header
#
# Quick install
#   curl -sSfLO 'https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/Scripts/apt-fuzz'
#   chmod +x ./apt-fuzz && ./apt-fuzz --install
#   source "~/.local/share/bash-completion/completions/apt-fuzz"   # to enable completion immediately
#
# Usage
#   ./apt-fuzz           # start interactive TUI
#   ./apt-fuzz --install # copy to ~/.local/bin/apt-fuzz and install user bash completion
#   ./apt-fuzz --uninstall # remove binary, completions, and cached previews (non-interactive)
#   ./apt-fuzz --preview <pkg>  # print cached preview (used by finder preview)
#   ./apt-fuzz install <pkg...> # non-interactive
#
# Environment variables
#   XDG_CACHE_HOME              (default: ~/.cache)
#   APT_FUZZ_CACHE_TTL          (seconds, default 86400 -> 1 day)
#   APT_FUZZ_CACHE_MAX_BYTES    (0 disables; default 0)
#   APT_FUZZ_FINDER_OPTS        (optional — overrides FINDER_BASE_OPTS at runtime)
#   APT_FUZZ_ANSI               (0/1 — adds --ansi to finder; default: 1)
#   APT_FUZZ_MANAGER            (force apt/nala/apt-fast; default: auto-detect)
#
# FINDER_BASE_OPTS — defaults and runtime override
#   We tune for speed and responsiveness on large inputs:
#     --layout=reverse-list : query line at bottom, list above (explicit layout)
#     --no-sort             : disables internal result re-sorting (faster). Tradeoff:
#                             you lose the final ranking pass; results follow input order.
#     --tiebreak=index      : cheap, deterministic tie-breaking
#     --no-hscroll          : avoids horizontal-scroll bookkeeping; faster redraws
#   Set $APT_FUZZ_FINDER_OPTS to fully replace these defaults if you prefer different behavior
#   (e.g., let the finder sort/rank results), and set $APT_FUZZ_ANSI=0 to drop --ansi.

set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C
: "${SHELL:=${BASH:-/bin/bash}}"
: "${XDG_CACHE_HOME:=${HOME:-$HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME%/}/apt-fuzz"
mkdir -p -- "$CACHE_DIR" &>/dev/null
: "${APT_FUZZ_CACHE_TTL:=86400}"
: "${APT_FUZZ_CACHE_MAX_BYTES:=0}"
# 0/1 flag
: "${APT_FUZZ_ANSI:=1}"

# Tool detection
if command -v sk &>/dev/null; then
  FINDER=sk
elif command -v fzf &>/dev/null; then
  FINDER=fzf
else
  echo "Please install skim (sk) or fzf." >&2; exit 1
fi
if command -v fd &>/dev/null; then
  FIND_TOOL="fd"
elif command -v fdfind &>/dev/null; then
  FIND_TOOL="fdfind"
else
  FIND_TOOL="find"
fi

# FINDER options (array)
FINDER_OPTS=(--layout=reverse-list --tiebreak=index --no-sort --no-hscroll)
if [[ "$APT_FUZZ_ANSI" == "1" ]]; then
  FINDER_OPTS+=(--ansi)
fi
if [[ -n ${APT_FUZZ_FINDER_OPTS:-} ]]; then
  # allow user to override completely (split into array)
  read -r -a FINDER_OPTS <<< "$APT_FUZZ_FINDER_OPTS"
fi

# Manager detection
HAS_NALA=0; HAS_APT_FAST=0
command -v nala &>/dev/null && HAS_NALA=1 || :
command -v apt-fast &>/dev/null && HAS_APT_FAST=1 || :
PRIMARY_MANAGER="${APT_FUZZ_MANAGER:-}"
if [[ -z $PRIMARY_MANAGER ]]; then
  PRIMARY_MANAGER=apt
  [[ $HAS_NALA -eq 1 ]] && PRIMARY_MANAGER=nala
  [[ $HAS_NALA -eq 0 && $HAS_APT_FAST -eq 1 ]] && PRIMARY_MANAGER=apt-fast
fi

# Utilities (pure bash reductions where possible)
total_bytes_in_dir(){
  local dir="$1" total=0 s f
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    # NUL-separated filenames at depth 1
    while IFS= read -r -d '' f; do
      s=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
      total=$(( total + s ))
    done < <("$FIND_TOOL" -0 -d 1 -t f . "$dir" 2>/dev/null || printf '')
  else
    while IFS= read -r -d '' f; do
      s=$(stat -c %s -- "$f" 2>/dev/null || echo 0)
      total=$(( total + s ))
    done < <(find "$dir" -maxdepth 1 -type f -print0 2>/dev/null || printf '')
  fi
  printf '%d' "$total"
}
byte_to_human(){
  local bytes="${1:-0}" i=0 pow=1
  local -a units=(B K M G T)
  while [[ $bytes -ge $(( pow * 1024 )) && $i -lt 4 ]]; do
    pow=$(( pow * 1024 )); i=$(( i + 1 ))
  done
  local value10=$(( (bytes * 10 + (pow / 2)) / pow ))
  local whole=$(( value10 / 10 )) dec=$(( value10 % 10 ))
  if (( dec > 0 )); then
    printf '%d.%d%s' "$whole" "$dec" "${units[i]}"
  else
    printf '%d%s' "$whole" "${units[i]}"
  fi
}

# Cache helpers
_cache_file_for(){ local pkg="$1"; printf '%s/%s.cache' "$CACHE_DIR" "${pkg//[^a-zA-Z0-9._+-]/_}"; }
_cache_mins(){ printf '%d' $(( (APT_FUZZ_CACHE_TTL + 59) / 60 )); }

evict_old_cache(){
  local mmin=$(( (APT_FUZZ_CACHE_TTL + 59) / 60 )) now=$(printf '%(%s)T' -1) cutoff total oldest min_mtime f ts m
  cutoff=$(( now - mmin*60 ))
  # Delete old cache files (fd/fdfind optimized, NUL-safe)
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    while IFS= read -r -d '' f; do
      ts=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
      if (( ts < cutoff )); then
        rm -f -- "$f" || :
      fi
    done < <("$FIND_TOOL" -0 -d 1 -t f . "$CACHE_DIR" 2>/dev/null || printf '')
  else
    find "$CACHE_DIR" -maxdepth 1 -type f -mmin +"$mmin" -delete 2>/dev/null || :
  fi
  # Evict by max bytes: delete oldest until under cap (pure-bash min reducer)
  if (( APT_FUZZ_CACHE_MAX_BYTES > 0 )); then
    total=$(total_bytes_in_dir "$CACHE_DIR")
    while (( total > APT_FUZZ_CACHE_MAX_BYTES )); do
      min_mtime=""
      oldest=""
      if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
        while IFS= read -r -d '' f; do
          m=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
          if [[ -z $min_mtime || $m -lt $min_mtime ]]; then
            min_mtime=$m; oldest="$f"
          fi
        done < <("$FIND_TOOL" -0 -d 1 -t f . "$CACHE_DIR" 2>/dev/null || printf '')
      else
        while IFS= read -r -d '' f; do
          m=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
          if [[ -z $min_mtime || $m -lt $min_mtime ]]; then
            min_mtime=$m; oldest="$f"
          fi
        done < <(find "$CACHE_DIR" -maxdepth 1 -type f -print0 2>/dev/null || printf '')
      fi

      [[ -z $oldest ]] && break
      rm -f -- "$oldest" || break
      total=$(total_bytes_in_dir "$CACHE_DIR")
    done
  fi
}
_cache_stats(){
  local files=0 size=$(total_bytes_in_dir "$CACHE_DIR") oldest age min_mtime f m
  size=${size:-0}
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    # count files
    while IFS= read -r -d '' f; do files=$(( files + 1 )); done < <("$FIND_TOOL" -0 -d 1 -t f . "$CACHE_DIR" 2>/dev/null || printf '')
    # find minimal mtime
    while IFS= read -r -d '' f; do
      m=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
      if [[ -z $min_mtime || $m -lt $min_mtime ]]; then min_mtime=$m; fi
    done < <("$FIND_TOOL" -0 -d 1 -t f . "$CACHE_DIR" 2>/dev/null || printf '')
    oldest="${min_mtime:-}"
  else
    while IFS= read -r -d '' f; do files=$(( files + 1 )); done < <(find "$CACHE_DIR" -maxdepth 1 -type f -print0 2>/dev/null || printf '')
    while IFS= read -r -d '' f; do
      m=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
      if [[ -z $min_mtime || $m -lt $min_mtime ]]; then min_mtime=$m; fi
    done < <(find "$CACHE_DIR" -maxdepth 1 -type f -print0 2>/dev/null || printf '')
    oldest="${min_mtime:-}"
  fi

  if [[ -z $oldest || $oldest -eq 0 ]]; then
    age="0m"
  else
    age=$(( ( (printf '%(%s)T' -1) - oldest ) / 60 ))m
  fi
  printf '%s|%s|%s' "$files" "$size" "$age"
}

# Preview generation (atomic)
_generate_preview(){
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="$(mktemp "${out}.XXXXXX.tmp")" || tmp="${out}.$$.$RANDOM.tmp"
  { apt-cache show "$pkg" 2>/dev/null || :; 
    printf '\n--- changelog (first 200 lines) ---\n'
    apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :; } >"$tmp" 2>/dev/null || :
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$out"; chmod 644 "$out" 2>/dev/null || :
}
_cached_preview_print(){
  local pkg="$1" f now f_mtime
  evict_old_cache
  f="$(_cache_file_for "$pkg")"
  now=$(printf '%(%s)T' -1)
  f_mtime=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
  if [[ -f $f ]] && (( now - f_mtime < APT_FUZZ_CACHE_TTL )); then
    cat "$f"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print

# Manager runner (apt-get for apt)
run_mgr(){
  local action="$1"; shift || :
  local pkgs=("$@") cmd=()
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
choose_manager(){
  local opts=(apt) choice
  [[ $HAS_NALA -eq 1 ]] && opts+=("nala")
  [[ $HAS_APT_FAST -eq 1 ]] && opts+=("apt-fast")
  choice=$(printf '%s\n' "${opts[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=12% --prompt="Manager> ")
  [[ -n $choice ]] && PRIMARY_MANAGER="$choice"
}

# Lists / helpers / UI (fd-native implementations when available)
list_all_packages(){
  # Try fd-native parsing of /var/lib/apt/lists/*Packages; fallback to apt-cache
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    local count=0 file pkg ver line
    while IFS= read -r -d '' file; do count=$((count+1)); done < <("$FIND_TOOL" -0 -g '*Packages' -d 1 -t f /var/lib/apt/lists 2>/dev/null || printf '')
    if (( count > 0 )); then
      while IFS= read -r -d '' file; do
        pkg=""; ver=""
        while IFS= read -r line || [[ -n $line ]]; do
          if [[ $line == Package:\ * ]]; then pkg=${line#Package: }; continue; fi
          if [[ $line == Version:\ * ]]; then ver=${line#Version: }; continue; fi
          if [[ -z $line && -n $pkg ]]; then
            printf '%s|%s\n' "$pkg" "${ver:-}"
            pkg=""; ver=""
          fi
        done < "$file"
        if [[ -n $pkg ]]; then printf '%s|%s\n' "$pkg" "${ver:-}"; fi
      done < <("$FIND_TOOL" -0 -g '*Packages' -d 1 -t f /var/lib/apt/lists 2>/dev/null || printf '')
      return 0
    fi
  fi
  # fallback
  apt-cache search . 2>/dev/null | sed -E 's/ - /|/; s/\t/ /g'
}
list_installed(){
  # fd-native: list files under /var/lib/dpkg/info/*.list -> pkg|installed
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    local count=0 f base
    while IFS= read -r -d '' f; do count=$((count+1)); done < <("$FIND_TOOL" -0 -g '*.list' -d 1 -t f /var/lib/dpkg/info 2>/dev/null || printf '')
    if (( count > 0 )); then
      while IFS= read -r -d '' f; do
        base="${f##*/}"
        printf '%s|installed\n' "${base%.list}"
      done < <("$FIND_TOOL" -0 -g '*.list' -d 1 -t f /var/lib/dpkg/info 2>/dev/null || printf '')
      return 0
    fi
  fi
  dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null || :
}
list_upgradable(){
  # fd-native: parse *_upgradable files; fallback to apt list --upgradable parsed in-shell
  if [[ "$FIND_TOOL" == "fd" || "$FIND_TOOL" == "fdfind" ]]; then
    local count=0 file line
    while IFS= read -r -d '' file; do count=$((count+1)); done < <("$FIND_TOOL" -0 -g '*_upgradable' -d 1 -t f /var/lib/apt/lists 2>/dev/null || printf '')
    if (( count > 0 )); then
      while IFS= read -r -d '' file; do
        while IFS= read -r line || [[ -n $line ]]; do
          if [[ $line == Package:\ * ]]; then printf '%s\n' "${line#Package: }"; fi
        done < "$file"
      done < <("$FIND_TOOL" -0 -g '*_upgradable' -d 1 -t f /var/lib/apt/lists 2>/dev/null || printf '')
      return 0
    fi
  fi
  local first=1 line pkg
  while IFS= read -r line || [[ -n $line ]]; do
    if (( first )); then first=0; continue; fi
    [[ -z $line ]] && continue
    pkg="${line%%/*}"
    printf '%s\n' "$pkg"
  done < <(apt list --upgradable 2>/dev/null || printf '')
}
backup_installed(){
  local out="${1:-pkglist-$(printf '%(%F)T' -1).txt}"
  dpkg-query -W -f='${binary:Package}\n' | sort -u >"$out"
  printf 'Saved: %s\n' "$out"
}
restore_from_file(){
  local file="$1"
  [[ ! -f $file ]] && { echo "File not found: $file" >&2; return 1; }
  mapfile -t pkgs < <(sed '/^$/d' "$file")
  [[ ${#pkgs[@]} -eq 0 ]] && { echo "No packages."; return 0; }
  mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --multi --height=40% --prompt="Confirm install> ")
  [[ ${#sel[@]} -eq 0 ]] && return
  run_mgr install "${sel[@]}"
}
show_changelog(){
  local pkg="$1"
  command -v apt-get &>/dev/null && (apt-get changelog "$pkg" 2>/dev/null || echo "No changelog for $pkg") || echo "apt-get unavailable"
}
action_menu_for_pkgs(){
  local pkgs=("$@") actions=(Install Remove Purge Changelog Cancel) act
  act=$(printf '%s\n' "${actions[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=12% --prompt="Action for ${#pkgs[@]} pkgs> ")
  [[ -z $act ]] && return
  case "$act" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) for p in "${pkgs[@]}"; do show_changelog "$p"; read -r -p "Enter to continue..." || :; done ;;
    Cancel) return ;;
  esac
}
_status_header(){
  local stats files size age human
  stats=$(_cache_stats)
  IFS='|' read -r files size age <<< "$stats"
  human=$(byte_to_human "$size")
  printf 'manager: %s | cache: %s files, %s, oldest: %s' "$PRIMARY_MANAGER" "$files" "$human" "$age"
}
menu_search_packages(){
  local header="$(_status_header)" sel pkgs
  # multi-select with TAB/Enter
  sel=$(list_all_packages \
      | "$FINDER" "${FINDER_OPTS[@]}" \
          --delimiter='|' --with-nth=1,2 \
          --preview "$0 --preview {1}" \
          --preview-window=right:60% \
          --multi --height=60% \
          --prompt="Search> " \
          --header="$header" \
          --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel" | cut -d'|' -f1)
  [[ ${#pkgs[@]} -eq 0 ]] && return
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_installed_packages(){
  local header="$(_status_header)" sel pkgs
  sel=$(list_installed \
      | sed 's/|/\t/' \
      | "$FINDER" "${FINDER_OPTS[@]}" \
          --with-nth=1,2 \
          --preview "$0 --preview {1}" \
          --preview-window=right:60% \
          --multi --height=60% \
          --prompt="Installed> " \
          --header="$header" \
          --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel" | cut -f1)
  [[ ${#pkgs[@]} -eq 0 ]] && return
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_upgradable(){
  local header="$(_status_header)" sel pkgs
  sel=$(list_upgradable \
      | "$FINDER" "${FINDER_OPTS[@]}" \
          --multi --height=40% \
          --prompt="Upgradable> " \
          --preview "$0 --preview {1}" \
          --preview-window=right:60% \
          --header="$header" \
          --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all')
  [[ -z $sel ]] && return
  mapfile -t pkgs < <(printf '%s\n' "$sel")
  [[ ${#pkgs[@]} -eq 0 ]] && return
  run_mgr install "${pkgs[@]}"
}
menu_backup_restore(){
  local opts=( "Backup installed packages" "Restore from file" "Cancel" ) choice
  choice=$(printf '%s\n' "${opts[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=12% --prompt="Backup/Restore> " --header="$(_status_header)")
  [[ -z $choice ]] && return
  case "$choice" in
    "Backup installed packages") backup_installed ;;
    "Restore from file") read -r -p "Path: " f; [[ -n $f ]] && restore_from_file "$f" ;;
  esac
}
menu_system_maintenance(){
  local opts=( Update Upgrade Autoremove Clean "Choose manager" Cancel ) choice
  choice=$(printf '%s\n' "${opts[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=18% --prompt="Maintenance> " --header="$(_status_header)")
  [[ -z $choice ]] && return
  case "$choice" in
    Update) run_mgr update ;;
    Upgrade) run_mgr upgrade ;;
    Autoremove) run_mgr autoremove ;;
    Clean) run_mgr clean ;;
    "Choose manager") choose_manager ;;
  esac
}
main_menu(){
  evict_old_cache
  local menu=( "Search packages" "Installed" "Upgradable" "Backup/Restore" "Maintenance" "Choose manager" "Quit" ) choice
  while true; do
    choice=$(printf '%s\n' "${menu[@]}" | "$FINDER" "${FINDER_OPTS[@]}" --height=20% --prompt="apt-fuzz> " --header="$(_status_header)")
    [[ -z $choice ]] && break
    case "$choice" in
      "Search packages") menu_search_packages ;;
      Installed) menu_installed_packages ;;
      Upgradable) menu_upgradable ;;
      "Backup/Restore") menu_backup_restore ;;
      Maintenance) menu_system_maintenance ;;
      "Choose manager") choose_manager ;;
      Quit) break ;;
    esac
  done
}

# Self-install / uninstall & completion
_install_self(){
  local dest="${HOME%/}/.local/bin/apt-fuzz" compdir="${HOME%/}/.local/share/bash-completion/completions"
  mkdir -p -- "${HOME%/}/.local/bin"
  cp -f -- "$0" "$dest"; chmod +x -- "$dest"; printf 'Installed: %s\n' "$dest"
  mkdir -p -- "$compdir"
  cat >"$compdir/apt-fuzz" <<'BASHCOMP'
_complete_apt_fuzz(){
  local cur="${COMP_WORDS[COMP_CWORD]}" opts="search installed upgradable install remove purge backup restore maintenance choose-manager quit"
  COMPREPLY=()
  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "${cur}") ); return 0
  fi
  case "${COMP_WORDS[1]}" in
    install|remove|purge) COMPREPLY=( $(compgen -W "$(apt-cache pkgnames | tr '\n' ' ')" -- "${cur}") ) ;;
    restore) COMPREPLY=( $(compgen -f -- "${cur}") ) ;;
  esac
}
complete -F _complete_apt_fuzz apt-fuzz
BASHCOMP
  printf 'Completion installed: %s/apt-fuzz\n' "$compdir"
}
_uninstall_self(){
  local dest="${HOME%/}/.local/bin/apt-fuzz" comp="${HOME%/}/.local/share/bash-completion/completions/apt-fuzz" cache="$CACHE_DIR"
  printf 'Uninstalling apt-fuzz...\n'
  rm -f -- "$dest"; rm -f -- "$comp"; rm -rf -- "$cache"
  printf 'Removed: %s\nRemoved: %s\nRemoved cache dir: %s\n' "$dest" "$comp" "$cache"
  printf 'Uninstall complete.\n'
}

# CLI conveniences
if [[ $# -gt 0 ]]; then
  case "$1" in
    --install) _install_self; exit 0 ;;
    --uninstall) _uninstall_self; exit 0 ;;
    --preview) [[ -z "${2:-}" ]] && { echo "usage: $0 --preview <pkg>" >&2; exit 2; }; _cached_preview_print "$2"; exit 0 ;;
    install|remove|purge) [[ $# -lt 2 ]] && { echo "Usage: $0 $1 <pkgs...>"; exit 2; }; cmd="$1"; shift; run_mgr "$cmd" "$@"; exit 0 ;;
    help|-h|--help) printf 'Usage: %s [--install] [--uninstall] | [install|remove|purge <pkgs...>]\nRun without args to start interactive TUI.\n' "$0"; exit 0 ;;
  esac
fi

cat <<'EOF'
apt-fuzz: sk/fzf frontend for apt/nala/apt-fast
Controls: fuzzy-search, multi-select (TAB), Enter to confirm
EOF

main_menu
