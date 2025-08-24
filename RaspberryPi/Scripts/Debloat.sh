#!/usr/bin/env bash
[[ $EUID -eq 0 ]] || { sudo "${0/#.\//$PWD/}" || { echo "Administrator privileges required"; exit 1; }; exit; }
export HOME="/home/${SUDO_USER:-$USER}" LC_ALL=C LANG=C

sudo apt-get purge -y libreoffice*

echo "Tweaks from https://privacy.sexy"
sudo apt-get purge -y reportbug
sudo apt-get purge -y python3-reportbug
sudo apt-get purge -y reportbug-gtk
sudo apt-get purge -y popularity-contest
echo '--- Disable participation in Popularity Contest'
if [[ -f /etc/popularity-contest.conf ]]; then
  sudo sed -i '/^PARTICIPATE=/d;$aPARTICIPATE=no' "/etc/popularity-contest.conf"
else
  echo "Skipping: '/etc/popularity-contest.conf' not found"
fi
echo '--- Remove daily cron entry for Popularity Contest (popcon)'
if [[ -f /etc/cron.daily/popularity-contest ]]; then
  [[ -x /etc/cron.daily/popularity-contest ]] && sudo chmod -x "/etc/cron.daily/popularity-contest" && echo "Disabled cronjob." || echo "Already disabled."
else
  echo "Cronjob not found."
fi

sudo apt-get autoclean -y
sudo apt-get autoremove -y
