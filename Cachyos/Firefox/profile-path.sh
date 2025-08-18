#!/usr/bin/env bash

firefox_profile() {
  local prof base="$HOME/.mozilla/firefox" 
  prof=$(awk -F= '
    /^\[Install/{f=1; next}
    /^\[/{f=0}
    f && /^Default=/{print $2; exit}' "$base/profiles.ini")
  [[ -n $prof ]] && echo "$base/$prof"
}
