#!/usr/bin/env bash
set -euo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8


sudo sed -i -e s"/\#LogFile.*/LogFile = /"g /etc/pacman.conf

