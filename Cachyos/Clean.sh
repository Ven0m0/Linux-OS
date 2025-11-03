#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar extglob
IFS=$'\n\t' SHELL="$(command -v bash 2>/dev/null | echo bash)"
export LC_ALL=C LANG=C LANGUAGE=C HOME="$/home/${SUDO_USER:-$USER}"
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
[[ $EUID -ne 0 ]] && sudo -v
#============ Color & Effects ============
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m' RED=$'\e[31m' GRN=$'\e[32m'
YLW=$'\e[33m' BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m' DEF=$'\e[0m' BLD=$'\e[1m'
has(){ command -v "$1" &>/dev/null; }

print_banner(){
  local banner
  banner=$(
    cat <<'EOF'
 ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗███╗   ██╗ ██████╗ 
██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║████╗  ██║██╔════╝ 
██║     ██║     █████╗  ███████║██╔██╗ ██║██║██╔██╗ ██║██║  ███╗
██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║██║╚██╗██║██║   ██║
╚██████╗███████╗███████╗██║  ██║██║ ╚████║██║██║ ╚████║╚██████╔╝
 ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
EOF
  )
  mapfile -t lines <<<"$banner"
  local flag_colors=("$LBLU" "$PNK" "$BWHT" "$PNK" "$LBLU")
  local line_count=${#lines[@]} segments=${#flag_colors[@]}
  if ((line_count <= 1)); then
    printf '%s%s%s\n' "${flag_colors[0]}" "${lines[0]}" "$DEF"
  else
    for i in "${!lines[@]}"; do
      local seg_idx=$((i * (segments - 1) / (line_count - 1)))
      ((seg_idx >= segments)) && seg_idx=$((segments - 1))
      printf '%s%s%s\n' "${flag_colors[seg_idx]}" "${lines[i]}" "$DEF"
    done
  fi
}

trap 'cleanup' EXIT INT TERM
cleanup(){ :; }

find_files(){
  if has fdf && [[ ! " $@ " =~ " --exec " ]]; then
    fdf -H --color=never "$@"
  elif has fd; then
    fd -H --color=never "$@"
  else
    find "$@"
  fi
}

capture_disk_usage(){
  local -n ref="$1"; ref=$(df -h --output=used,pcent / 2>/dev/null | awk 'NR==2{print $1, $2}')
}

ensure_not_running(){
  local process_name=$1 timeout=6
  if pgrep -x -u "$USER" "$process_name" &>/dev/null; then
    printf '  %b\n' "${YLW}Waiting for ${process_name} to exit...${DEF}"
    while ((timeout-- > 0)) && pgrep -x -u "$USER" "$process_name" &>/dev/null; do
      read -rt 1 -- <> <(:) &>/dev/null || :
    done
    if pgrep -x -u "$USER" "$process_name" &>/dev/null; then
      printf '  %b\n' "${RED}Killing ${process_name}...${DEF}"
      pkill -KILL -x -u "$USER" "$process_name" &>/dev/null || :
      read -rt 1 -- <> <(:) &>/dev/null || :
    fi
  fi
}

clean_sqlite_dbs(){
  local db diff s_old s_new total_saved=0
  while read -r db; do
    s_old=$(stat -c%s "$db" 2>/dev/null) || continue
    sqlite3 "$db" "VACUUM; REINDEX;" &>/dev/null || continue
    s_new=$(stat -c%s "$db" 2>/dev/null) || s_new=$s_old
    diff=$((s_old - s_new))
    total_saved=$((total_saved + diff))
  done < <(find_files . -maxdepth 1 -type f -print0 | xargs -0r file -e ascii | sed -n 's/:.*SQLite.*//p')
  if ((total_saved > 0)); then
    printf '  %b\n' "${GRN}Vacuumed SQLite DBs, saved $((total_saved / 1024)) KB${DEF}"
  fi
}
clean_browsers(){
  printf '%b\n' "🔄${BLU}Cleaning browser data...${DEF}"
  local user_home="${1:-$HOME}"
  # Browser definitions: "executable_name;config_root;type"
  # type: mozilla, mozilla_standalone, chrome
  local browsers=(
    "firefox;${user_home}/.mozilla/firefox;mozilla"
    "librewolf;${user_home}/.librewolf;mozilla_standalone"
    "floorp;${user_home}/.floorp;mozilla_standalone"
    "waterfox;${user_home}/.waterfox;mozilla_standalone"
    "google-chrome;${user_home}/.config/google-chrome;chrome"
    "chromium;${user_home}/.config/chromium;chrome"
    "brave-browser;${user_home}/.config/BraveSoftware/Brave-Browser;chrome"
  )
  for browser_def in "${browsers[@]}"; do
    IFS=';' read -r name config_root type <<<"$browser_def"
    [[ ! -d "$config_root" ]] && continue
    ensure_not_running "$name"
    printf '  %b\n' "${CYN}Cleaning ${name} profiles...${DEF}"
    if [[ "$type" == "mozilla" || "$type" == "mozilla_standalone" ]]; then
      local profile_base_dir="$config_root"
      [[ "$type" == "mozilla_standalone" ]] && profile_base_dir="${config_root}/"
      local installs_ini="${config_root}/installs.ini"
      local profiles_ini="${config_root}/profiles.ini"
      declare -A seen_profiles
      # Modern method (Firefox)
      if [[ -f "$installs_ini" ]]; then
        while read -r path; do
          [[ -n "$path" && -z "${seen_profiles[$path]}" ]] && {
            (cd "${profile_base_dir}${path}" && clean_sqlite_dbs)
            seen_profiles[$path]=1
          }
        done < <(awk -F= '/^Default=/{print $2}' "$installs_ini" 2>/dev/null)
      fi
      # Legacy/fork method
      if [[ -f "$profiles_ini" ]]; then
        while read -r path; do
          [[ -n "$path" && -z "${seen_profiles[$path]}" ]] && {
            (cd "${profile_base_dir}${path}" && clean_sqlite_dbs)
            seen_profiles[$path]=1
          }
        done < <(awk -F= '/^Path=/{print $2}' "$profiles_ini" 2>/dev/null)
      fi
    elif [[ "$type" == "chrome" ]]; then
      while read -r profile_dir; do
        (cd "$profile_dir" && clean_sqlite_dbs)
      done < <(find_files "$config_root" -maxdepth 1 -type d \( -name "Default" -o -name "Profile *" \))
    fi
  done
}

main(){
  print_banner
  local disk_before disk_after space_before space_after
  capture_disk_usage disk_before
  space_before=$(sudo du -sh / 2>/dev/null | cut -f1)

  if has modprobed-db; then
    printf '%b\n' "🔄${BLU}Storing kernel modules...${DEF}"
    modprobed-db store &>/dev/null && sudo modprobed-db store &>/dev/null
  fi
  printf '%b\n' "🔄${BLU}Flushing network caches...${DEF}"
  sudo resolvectl flush-caches &>/dev/null || :
  sudo systemd-resolve --flush-caches &>/dev/null || :
  sudo systemd-resolve --reset-statistics &>/dev/null || :
  
  printf '%b\n' "🔄${BLU}Removing orphaned packages...${DEF}"
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || :)
  if [[ ${#orphans[@]} -gt 0 ]]; then
    sudo pacman -Rns --noconfirm "${orphans[@]}" &>/dev/null || :
  fi

  printf '%b\n' "🔄${BLU}Cleaning package caches...${DEF}"
  sudo find -O2 /etc/pacman.d -maxdepth 1 -type f -name '*.bak' -delete &>/dev/null
  paru -Scc --noconfirm &>/dev/null || sudo pacman -Scc --noconfirm &>/dev/null
  sudo paccache -rk0 -q &>/dev/null || :

  has uv && uv clean -q
  if has cargo-cache; then
    printf '%b\n' "🔄${BLU}Cleaning Cargo cache...${DEF}"
    cargo cache -efg &>/dev/null; cargo cache -ef trim --limit 1B &>/dev/null
  fi
  has bun && bun pm cache rm &>/dev/null
  has pnpm && { pnpm prune  &>/dev/null && pnpm store prune &>/dev/null; }
  has sdk && sdk flush tmp &>/dev/null

  printf '%b\n' "🔄${BLU}Resetting swap space...${DEF}"
  sudo swapoff -a &>/dev/null && sudo swapon -a &>/dev/null

  printf '%b\n' "🔄${BLU}Cleaning old logs and crash dumps...${DEF}"
  sudo find /var/log/ -name "*.log" -type f -mtime +7 -delete &>/dev/null || :
  sudo journalctl --rotate --vacuum-size=10M -q &>/dev/null

  printf '%b\n' "🔄${BLU}Cleaning user and system caches...${DEF}"
  sudo systemd-tmpfiles --clean &>/dev/null || :
  find_files "${HOME}/.cache" -type f -mtime +1 -delete &>/dev/null || :
  find_files "${HOME}/.cache" -type d -empty -delete &>/dev/null || :

  local safe_remove_paths=(
    "${HOME}/.local/share/Trash/"*
    "${HOME}/.thumbnails/"*
    "${HOME}/.var/app/"*/cache/*
    "${HOME}/.config/Trolltech.conf"
    "${HOME}/.local/share/Steam/appcache/"*
    "${HOME}/.nv/ComputeCache/"*
  )
  for path in "${safe_remove_paths[@]}"; do rm -rf -- "$path" &>/dev/null; done

  sudo rm -rf /root/.local/share/Trash/* &>/dev/null
  sudo rm -rf /var/tmp/flatpak-cache-* &>/dev/null
  has flatpak && flatpak uninstall --unused --delete-data -y &>/dev/null

  printf '%b\n' "🔄${BLU}Cleaning shell history files...${DEF}"
  local history_files=(.bash_history .zsh_history .history .local/share/fish/fish_history .config/fish/fish_history .wget-hsts .lesshst)
  for file in "${history_files[@]}"; do
    rm -f -- "${HOME}/${file}" &>/dev/null
    sudo rm -f -- "/root/${file}" &>/dev/null
  done
  touch "${HOME}/.python_history" && sudo chattr +i "${HOME}/.python_history" &>/dev/null

  clean_browsers "$HOME"

  if has bleachbit; then
    printf '%b\n' "🔄${BLU}Running BleachBit...${DEF}"
    bleachbit -c --preset &>/dev/null || :
    sudo bleachbit -c --preset &>/dev/null || :
  fi

  sudo fstrim -a --quiet-unsupported &>/dev/null || :
  sudo fc-cache -r &>/dev/null || :

  capture_disk_usage disk_after
  space_after=$(sudo du -sh / 2>/dev/null | cut -f1)

  printf '\n%b\n' "${GRN}System cleaned!${DEF}"
  printf '==> %b %s\n' "${BLU}Disk usage before:${DEF}" "${disk_before}"
  printf '==> %b %s\n' "${GRN}Disk usage after: ${DEF}" "${disk_after}"
  printf '\n%b\n' "${BLU}Total space before/after:${DEF}"
  printf '%b %s\n' "${YLW}Before:${DEF}" "${space_before}"
  printf '%b %s\n' "${GRN}After: ${DEF}" "${space_after}"
}

main "$@"
