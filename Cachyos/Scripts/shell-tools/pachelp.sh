#!/usr/bin/env bash
export LC_ALL="C"
set -euo pipefail; shopt -s nullglob globstar
# IFS=$'\n\t'
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "This script requires root privileges. Validating with sudo..."
  sudo -v || { echo "Sudo failed. Exiting."; exit 1; }
fi


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
