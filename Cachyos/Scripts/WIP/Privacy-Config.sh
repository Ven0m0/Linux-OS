#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Color definitions
YLW=$'\e[33m'
MGN=$'\e[35m'
GRN=$'\e[32m'
CYN=$'\e[36m'
DEF=$'\e[0m'

# Check if command exists
has(){ command -v "$1" &>/dev/null; }

# Override HOME for SUDO_USER context
export HOME="/home/${SUDO_USER:-$USER}"

print_banner(){
  cat <<'EOF'
🔒 Privacy Configuration Script
================================
EOF
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
