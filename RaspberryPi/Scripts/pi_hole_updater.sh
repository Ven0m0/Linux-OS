#!/bin/bash
# Script Name: pi_hole_updater.sh
# Description: Robust Pi-hole + System updater for Raspberry Pi OS or Debian-based systems.
# https://github.com/r0xd4n3t/pi-hole-maintenance
# Author: r0xd4n3t
# Date: 02 JUL 2025

# Check for root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root. Exiting." >&2
    exit 1
fi

# Verify OS
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID:-}" != "raspbian" && "${ID_LIKE:-}" != *"debian"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | OS '${PRETTY_NAME:-$NAME}' not supported. Exiting." >> logs.log
        exit 0
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') | OS verification failed. Exiting." >> logs.log
    exit 0
fi

# Log setup
LOG_FILE="logs.log"
MAX_OLD_LOGS=5

if [[ -f "$LOG_FILE" ]]; then
    if [[ -f "${LOG_FILE}.${MAX_OLD_LOGS}" ]]; then
        rm -f "${LOG_FILE}.${MAX_OLD_LOGS}"
    fi
    for (( i=MAX_OLD_LOGS-1; i>=1; i-- )); do
        if [[ -f "${LOG_FILE}.${i}" ]]; then
            mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))"
        fi
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
fi

# Timestamped logging
log() {
    local TIMESTAMP
    TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${TIMESTAMP} | $*" | tee -a "$LOG_FILE"
}

timestamp_output() {
    while IFS= read -r line; do
        printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line"
    done
}

# Begin main work
log "=== Starting update process ==="

# Update system packages
log "Updating package list (apt-get update)..."
apt-get update 2>&1 | timestamp_output | tee -a "$LOG_FILE"
apt_update_status=${PIPESTATUS[0]}
if [[ $apt_update_status -ne 0 ]]; then
    log "ERROR: 'apt-get update' failed. Skipping upgrade."
else
    log "'apt-get update' completed."

    log "Upgrading installed packages (apt-get full-upgrade)..."
    apt-get full-upgrade -y 2>&1 | timestamp_output | tee -a "$LOG_FILE"
    apt_upgrade_status=${PIPESTATUS[0]}
    if [[ $apt_upgrade_status -ne 0 ]]; then
        log "ERROR: 'apt-get full-upgrade' failed."
    else
        log "System packages upgraded successfully."
    fi
fi

# Update Pi-hole if available
if command -v pihole > /dev/null 2>&1; then
    log "Pi-hole is installed. Updating..."
    pihole -up 2>&1 | timestamp_output | tee -a "$LOG_FILE"
    pihole_update_status=${PIPESTATUS[0]}
    if [[ $pihole_update_status -ne 0 ]]; then
        log "ERROR: Pi-hole update failed."
    else
        log "Pi-hole updated successfully."
    fi
else
    log "Pi-hole not found. Skipping Pi-hole update."
fi

# Check if reboot required
if [[ -f /var/run/reboot-required ]]; then
    log "Reboot required. System will reboot now."
    sync
    /sbin/shutdown -r now "Rebooting after updates"
else
    log "No reboot required."
    log "=== Update process completed successfully ==="
fi
