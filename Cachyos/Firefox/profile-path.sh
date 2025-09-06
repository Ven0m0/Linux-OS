#!/usr/bin/env bash

foxdir(){
  local PROFILE_DIR="${HOME}/.mozilla/firefox" ACTIVE_PROF ACTIVE_PROF_DIR
  ACTIVE_PROF=$(awk -F= '/^\[.*\]/{f=0} /^\[Install/{f=1; next} f && /^Default=/{print $2; exit}' "${PROFILE_DIR}/installs.ini" 2>/dev/null)
  [[ -z "$ACTIVE_PROF" ]] && { ACTIVE_PROF=$(awk -F= '/^\[.*\]/{f=0} /^\[Profile[0-9]+\]/{f=1} f && /^Default=1/ {found=1} f && /^Path=/{if(found){print $2; exit}}' "${PROFILE_DIR}/profiles.ini" 2>/dev/null); }
  [[ -n "$ACTIVE_PROF" ]] && { ACTIVE_PROF_DIR="${PROFILE_DIR}/${ACTIVE_PROF}"; export ACTIVE_PROF_DIR; } || { echo "❌ Could not determine active Firefox profile." >&2; exit 1; }
}
FOXYDIR="$(foxdir)"
