#!/usr/bin/env bash
#|---/ /+---------------------+---/ /|#
#|--/ /-| PKG-Manager wrapper |--/ /-|#
#|/ /---+---------------------+/ /---|#
# Credit:
# https://github.com/ekahPruthvi/cynageOS/

#---Setup---
export LC_ALL="C"
set -euo pipefail; shopt -s nullglob globstar
# IFS=$'\n\t'
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Validating with sudo..."
  sudo -v || { echo "Sudo failed. Exiting."; exit 1; }
fi
#------
service_ctl()
{
    local ServChk=$1

    if [[ $(systemctl list-units --all -t service --full --no-legend "${ServChk}.service" | sed 's/^\s*//g' | cut -f1 -d' ') == "${ServChk}.service" ]]
    then
        echo "$ServChk service is already enabled, enjoy..."
    else
        echo "$ServChk service is not running, enabling..."
        sudo systemctl enable ${ServChk}.service
        sudo systemctl start ${ServChk}.service
        echo "$ServChk service enabled, and running..."
    fi
}
pkg_installed()
{
    local PkgIn=$1

    if pacman -Qi $PkgIn &> /dev/null
    then
        #echo "${PkgIn} is already installed..."
        return 0
    else
        #echo "${PkgIn} is not installed..."
        return 1
    fi
}

pkg_available()
{
    local PkgIn=$1

    if pacman -Si $PkgIn &> /dev/null
    then
        #echo "${PkgIn} available in arch repo..."
        return 0
    else
        #echo "${PkgIn} not available in arch repo..."
        return 1
    fi
}
aur_available()
{
    local PkgIn=$1
    chk_aurh

    if $aurhlpr -Si $PkgIn &> /dev/null
    then
        #echo "${PkgIn} available in aur repo..."
        return 0
    else
        #echo "aur helper is not installed..."
        return 1
    fi
}
nvidia_detect()
{
    if [ `lspci -k | grep -A 2 -E "(VGA|3D)" | grep -i nvidia | wc -l` -gt 0 ]
    then
        #echo "nvidia card detected..."
        return 0
    else
        #echo "nvidia card not detected..."
        return 1
    fi
}
