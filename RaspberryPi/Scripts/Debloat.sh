#!/usr/bin/env bash
export HOME="/home/${SUDO_USER:-$USER}" LC_ALL=C LANG=C
sudo -v


sudo apt-get purge -y libreoffice*
echo "Tweaks from https://privacy.sexy"
sudo apt-get purge -y reportbug python3-reportbug reportbug-gtk apport whoopsie popularity-contest
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
