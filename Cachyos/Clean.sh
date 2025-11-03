#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar extglob
IFS=$'\n\t' SHELL="$(command -v bash 2>/dev/null)"
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD" || exit 1
[[ $EUID -ne 0 ]] && sudo -v
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches &>/dev/null
#============ Color & Effects ============
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' DEF=$'\e[0m'
has(){ command -v "$1" &>/dev/null; }

print_banner(){
  cat <<'EOF'
🧹 Privacy Cleanup Script
========================
EOF
}
glob_rm(){ local pattern=$1; eval "rm -rf $pattern" &>/dev/null || :; }
py_glob_rm(){
  local pattern=$1; has python3 || { printf '%b\n' "${YLW}Skipping glob (no python3): $pattern${DEF}"; return; }
  python3 <<EOF
import glob, os
path='$pattern'
expanded=os.path.expandvars(os.path.expanduser(path))
paths=glob.glob(expanded)
if not paths: exit(0)
for p in paths:
  if not os.path.isfile(p): continue
  try: os.remove(p)
  except: pass
EOF
}

main(){
  print_banner
  local items_cleaned=0
  
  printf '%b\n' "${BLU}Shell history...${DEF}"
  rm -f ~/.{bash,zsh}_history ~/.history ~/.local/share/fish/fish_history ~/.config/fish/fish_history ~/.wget-hsts ~/.lesshst &>/dev/null && ((items_cleaned++))
  sudo rm -f /root/.{bash,zsh}_history /root/.history /root/.local/share/fish/fish_history /root/.config/fish/fish_history &>/dev/null
  
  printf '%b\n' "${BLU}Python history (immutable)...${DEF}"
  rm -f ~/.python_history &>/dev/null
  sudo rm -f /root/.python_history &>/dev/null
  touch ~/.python_history && sudo chattr +i ~/.python_history &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Privacy.sexy runs & logs...${DEF}"
  glob_rm '$HOME/.config/privacy.sexy/runs/*'
  glob_rm '$HOME/.config/privacy.sexy/logs/*' && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Wine/Winetricks...${DEF}"
  rm -rf ~/.wine/drive_c/windows/temp/* ~/.cache/{wine,winetricks}/ &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}VSCode crash reports, cache & logs...${DEF}"
  glob_rm '~/.config/Code/{Crash\ Reports,exthost\ Crash\ Reports,Cache,CachedData,Code\ Cache,GPUCache,CachedExtensions,CachedExtensionVSIXs,logs}/*'
  glob_rm '~/.var/app/com.visualstudio.code/config/Code/{Crash\ Reports,exthost\ Crash\ Reports,Cache,CachedData,Code\ Cache,GPUCache,CachedExtensions,CachedExtensionVSIXs,logs}/*' && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Steam cache...${DEF}"
  rm -rf ~/.local/share/Steam/appcache/* ~/snap/steam/common/{.cache,.local/share/Steam/appcache}/* ~/.var/app/com.valvesoftware.Steam/{cache,data/Steam/appcache}/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}LibreOffice usage history...${DEF}"
  rm -f ~/.config/libreoffice/4/user/registrymodifications.xcu ~/snap/libreoffice/*/.config/libreoffice/4/user/registrymodifications.xcu ~/.var/app/org.libreoffice.LibreOffice/config/libreoffice/4/user/registrymodifications.xcu &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Firefox cache & crash reports...${DEF}"
  rm -rf ~/.cache/mozilla/* ~/.var/app/org.mozilla.firefox/cache/* ~/snap/firefox/common/.cache/* &>/dev/null
  rm -rf ~/.mozilla/firefox/Crash\ Reports/* ~/.var/app/org.mozilla.firefox/.mozilla/firefox/Crash\ Reports/* ~/snap/firefox/common/.mozilla/firefox/Crash\ Reports/* &>/dev/null
  py_glob_rm '~/.mozilla/firefox/*/crashes/*'
  py_glob_rm '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/*'
  py_glob_rm '~/snap/firefox/common/.mozilla/firefox/*/crashes/*'
  py_glob_rm '~/.mozilla/firefox/*/crashes/events/*'
  py_glob_rm '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/crashes/events/*'
  py_glob_rm '~/snap/firefox/common/.mozilla/firefox/*/crashes/events/*'
  py_glob_rm '~/.mozilla/firefox/*/containers.json'
  py_glob_rm '~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/containers.json'
  py_glob_rm '~/snap/firefox/common/.mozilla/firefox/*/containers.json' && ((items_cleaned++))
  
  printf '%b\n' "${BLU}GNOME Web cache & history...${DEF}"
  rm -rf ~/.cache/epiphany/* ~/.var/app/org.gnome.Epiphany/cache/* ~/snap/epiphany/common/.cache/* &>/dev/null
  rm -f ~/.local/share/epiphany/ephy-history.db{,-shm,-wal} ~/.var/app/org.gnome.Epiphany/data/epiphany/ephy-history.db{,-shm,-wal} ~/snap/epiphany/*/.local/share/epiphany/ephy-history.db{,-shm,-wal} &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}System crash reports & logs...${DEF}"
  sudo rm -rf /var/crash/* /var/lib/systemd/coredump/ &>/dev/null
  has journalctl && sudo journalctl --vacuum-time=1s &>/dev/null
  sudo rm -rf /run/log/journal/* /var/log/journal/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Zeitgeist activity logs...${DEF}"
  sudo rm -rf {/root,/home/*}/.local/share/zeitgeist &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}GTK recent files...${DEF}"
  rm -f ~/.recently-used.xbel ~/.local/share/recently-used.xbel* ~/snap/*/*/.local/share/recently-used.xbel ~/.var/app/*/data/recently-used.xbel &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}KDE recent documents...${DEF}"
  rm -rf ~/.local/share/RecentDocuments/*.desktop ~/.kde{,4}/share/apps/RecentDocuments/*.desktop ~/snap/*/*/.local/share/*.desktop ~/.var/app/*/data/*.desktop &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Snap cache...${DEF}"
  sudo rm -rf /var/lib/snapd/cache/* &>/dev/null
  if has snap; then
    snap list --all | while read -r name version rev tracking publisher notes; do
      [[ $notes == *disabled* ]] && sudo snap remove "$name" --revision="$rev" &>/dev/null || :
    done
  fi
  rm -rf ~/snap/*/*/.cache/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Flatpak cache...${DEF}"
  sudo rm -rf /var/tmp/flatpak-cache-* &>/dev/null
  rm -rf ~/.cache/flatpak/system-cache/* ~/.local/share/flatpak/system-cache/* ~/.var/app/*/cache/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Global temp folders...${DEF}"
  sudo rm -rf /tmp/* /var/tmp/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}User cache...${DEF}"
  rm -rf ~/.cache/* &>/dev/null
  sudo rm -rf /root/.cache/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}System cache...${DEF}"
  sudo rm -rf /var/cache/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Thumbnails...${DEF}"
  rm -rf ~/.thumbnails/* ~/.cache/thumbnails/* &>/dev/null && ((items_cleaned++))
  
  printf '%b\n' "${BLU}Trash...${DEF}"
  rm -rf ~/.local/share/Trash/* ~/snap/*/*/.local/share/Trash/* ~/.var/app/*/data/Trash/* &>/dev/null
  sudo rm -rf /root/.local/share/Trash/* &>/dev/null && ((items_cleaned++))
  
  printf '\n%b\n' "${GRN}✓ Privacy cleanup complete! ($items_cleaned categories)${DEF}"
}

main "$@"
