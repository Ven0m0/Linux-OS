#!/usr/bin/env bash
# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || exit 1

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

print_banner(){
  cat <<'EOF'
🔒 Privacy Configuration Script
================================
EOF
}

vscode_json_set(){
  local prop=$1 val=$2
  has python3 || { printf '%b\n' "${YLW}Skipping VSCode setting (no python3): $prop${DEF}"; return 1; }
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name='$prop'
target=json.loads('$val')
home_dir=f'/home/{os.getenv("SUDO_USER",os.getenv("USER"))}'
settings_files=[
  f'{home_dir}/.config/Code/User/settings.json',
  f'{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json'
]
changed=0
for sf in settings_files:
  file=Path(sf)
  if not file.exists():
    file.parent.mkdir(parents=True,exist_ok=True)
    file.write_text('{}')
  content=file.read_text()
  if not content.strip(): content='{}'
  try: obj=json.loads(content)
  except json.JSONDecodeError:
    print(f'Invalid JSON in {sf}',file=sys.stderr)
    continue
  if property_name in obj and obj[property_name]==target: continue
  obj[property_name]=target
  file.write_text(json.dumps(obj,indent=2))
  changed+=1
sys.exit(0 if changed>0 else 1)
EOF
  return $?
}

configure_vscode(){
  printf '%b\n' "${MGN}Configuring VSCode privacy settings...${DEF}"
  local settings_changed=0
  
  local settings=(
    'telemetry.telemetryLevel;"off"'
    'telemetry.enableTelemetry;false'
    'telemetry.enableCrashReporter;false'
    'workbench.enableExperiments;false'
    'update.mode;"none"'
    'update.channel;"none"'
    'update.showReleaseNotes;false'
    'npm.fetchOnlinePackageInfo;false'
    'git.autofetch;false'
    'workbench.settings.enableNaturalLanguageSearch;false'
    'typescript.disableAutomaticTypeAcquisition;true'
    'workbench.experimental.editSessions.enabled;false'
    'workbench.experimental.editSessions.autoStore;false'
    'workbench.editSessions.autoResume;false'
    'workbench.editSessions.continueOn;false'
    'extensions.autoUpdate;false'
    'extensions.autoCheckUpdates;false'
    'extensions.showRecommendationsOnlyOnDemand;true'
  )
  
  for setting in "${settings[@]}"; do
    IFS=';' read -r prop val <<<"$setting"
    if vscode_json_set "$prop" "$val"; then
      printf '  %b %s\n' "${GRN}✓${DEF}" "$prop"
      ((settings_changed++))
    else
      printf '  %b %s\n' "${CYN}→${DEF}" "$prop"
    fi
  done
  
  printf '%b\n' "${GRN}VSCode: $settings_changed settings changed${DEF}"
}

configure_firefox(){
  printf '%b\n' "${MGN}Configuring Firefox privacy settings...${DEF}"
  local prefs_changed=0
  
  # Firefox prefs.js hardening (minimal selection from arkenfox/user.js)
  local firefox_prefs=(
    'user_pref("browser.startup.homepage_override.mstone", "ignore");'
    'user_pref("browser.newtabpage.enabled", false);'
    'user_pref("browser.newtabpage.activity-stream.showSponsored", false);'
    'user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);'
    'user_pref("geo.enabled", false);'
    'user_pref("geo.provider.network.url", "");'
    'user_pref("browser.search.suggest.enabled", false);'
    'user_pref("network.dns.disablePrefetch", true);'
    'user_pref("network.prefetch-next", false);'
    'user_pref("network.predictor.enabled", false);'
    'user_pref("dom.battery.enabled", false);'
    'user_pref("privacy.resistFingerprinting", true);'
    'user_pref("privacy.trackingprotection.enabled", true);'
    'user_pref("privacy.trackingprotection.socialtracking.enabled", true);'
    'user_pref("beacon.enabled", false);'
  )
  
  local firefox_dirs=(
    ~/.mozilla/firefox
    ~/.var/app/org.mozilla.firefox/.mozilla/firefox
    ~/snap/firefox/common/.mozilla/firefox
  )
  
  for dir in "${firefox_dirs[@]}"; do
    [[ ! -d $dir ]] && continue
    while IFS= read -r profile; do
      local prefs_file="$profile/user.js"
      touch "$prefs_file"
      for pref in "${firefox_prefs[@]}"; do
        if ! grep -qF "$pref" "$prefs_file" 2>/dev/null; then
          echo "$pref" >> "$prefs_file"
          ((prefs_changed++))
        fi
      done
      printf '  %b %s\n' "${GRN}✓${DEF}" "$profile"
    done < <(find "$dir" -maxdepth 1 -type d -name "*.default*" -o -name "default-*")
  done
  
  printf '%b\n' "${GRN}Firefox: $prefs_changed preferences set${DEF}"
}

configure_python_history(){
  printf '%b\n' "${MGN}Disabling Python history...${DEF}"
  local history_file="$HOME/.python_history"
  if [[ ! -f $history_file ]]; then
    touch "$history_file"
    printf '  %b\n' "${GRN}✓ Created $history_file${DEF}"
  fi
  if sudo chattr +i "$history_file" &>/dev/null; then
    printf '  %b\n' "${GRN}✓ Made immutable${DEF}"
  else
    printf '  %b\n' "${YLW}⚠ Could not set immutable (chattr not available)${DEF}"
  fi
}

main(){
  print_banner
  local total_changes=0
  
  configure_vscode || :
  configure_firefox || :
  configure_python_history || :
  
  printf '\n%b\n' "${GRN}✓ Privacy configuration complete!${DEF}"
  printf '%b\n' "${CYN}Run Privacy-Clean.sh to remove historical data${DEF}"
}

main "$@"