#!/usr/bin/env bash

PROFILE_DIR="${HOME}/.mozilla/firefox"
ACTIVE_PROF=$(awk -F= '/^Default=/ {print $2}' "${PROFILE_DIR}/installs.ini")
#ACTIVE_PROF=$(awk -F= ' /^\[Install/{f=1; next} /^\[/{f=0} f && /^Default=/{print $2; exit}' "${PROFILE_DIR}/profiles.ini")

echo "${PROFILE_DIR}/${ACTIVE_PROFILE}"
PROFILE_DIR="${HOME}/.mozilla/firefox"
[[ -n $AVTIVE_PROF ]] && APROF_DIR="$(echo "${PROFILE_DIR}/${ACTIVE_PROFILE}")"
