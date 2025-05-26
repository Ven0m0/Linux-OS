#!/usr/bin/env bash
# https://privacy.sexy — v0.13.8 — Mon, 19 May 2025 19:20:17 GMT
if [ "$EUID" -ne 0 ]; then
  script_path=$([[ "$0" = /* ]] && echo "$0" || echo "$PWD/${0#./}")
  sudo "$script_path" || (
    echo 'Administrator privileges are required.'
    exit 1
  )
  exit 0
fi
export HOME="/home/${SUDO_USER:-${USER}}" # Keep `~` and `$HOME` for user not `/root`.

# ----------------------------------------------------------
# --Disable Python history for future interactive commands--
# ----------------------------------------------------------
echo '--- Disable Python history for future interactive commands'
history_file="$HOME/.python_history"
if [ ! -f "$history_file" ]; then
  touch "$history_file"
  echo "Created $history_file."
fi
sudo chattr +i "$(realpath $history_file)" # realpath in case of symlink
# ----------------------------------------------------------

# ----------------------------------------------------------
# -------Disable participation in Popularity Contest--------
# ----------------------------------------------------------
echo '--- Disable participation in Popularity Contest'
config_file='/etc/popularity-contest.conf'
if [ -f "$config_file" ]; then
  sudo sed -i '/PARTICIPATE/c\PARTICIPATE=no' "$config_file"
else
  echo "Skipping because configuration file at ($config_file) is not found. Is popcon installed?"
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# -------Remove Popularity Contest (`popcon`) package-------
# ----------------------------------------------------------
echo '--- Remove Popularity Contest (`popcon`) package'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  apt_package_name='popularity-contest'
if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$apt_package_name" 2>&1)" \
    && [ "$status" = installed ]; then
  echo "\"$apt_package_name\" is installed and will be uninstalled."
  sudo apt-get purge -y "$apt_package_name"
else
  echo "Skipping, no action needed, \"$apt_package_name\" is not installed."
fi
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# -Remove daily cron entry for Popularity Contest (popcon)--
# ----------------------------------------------------------
echo '--- Remove daily cron entry for Popularity Contest (popcon)'
job_name='popularity-contest'
cronjob_path="/etc/cron.daily/$job_name"
if [[ -f "$cronjob_path" ]]; then
  if [[ -x "$cronjob_path" ]]; then
    sudo chmod -x "$cronjob_path"
    echo "Successfully disabled cronjob \"$job_name\"."
  else
    echo "Skipping, cronjob \"$job_name\" is already disabled."
  fi
else
  echo "Skipping, \"$job_name\" cronjob is not found."
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# ----------------Remove `reportbug` package----------------
# ----------------------------------------------------------
echo '--- Remove `reportbug` package'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  apt_package_name='reportbug'
if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$apt_package_name" 2>&1)" \
    && [ "$status" = installed ]; then
  echo "\"$apt_package_name\" is installed and will be uninstalled."
  sudo apt-get purge -y "$apt_package_name"
else
  echo "Skipping, no action needed, \"$apt_package_name\" is not installed."
fi
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# ----------Remove Python modules for `reportbug`-----------
# ----------------------------------------------------------
echo '--- Remove Python modules for `reportbug`'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  apt_package_name='python3-reportbug'
if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$apt_package_name" 2>&1)" \
    && [ "$status" = installed ]; then
  echo "\"$apt_package_name\" is installed and will be uninstalled."
  sudo apt-get purge -y "$apt_package_name"
else
  echo "Skipping, no action needed, \"$apt_package_name\" is not installed."
fi
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# ----Remove UI for reportbug (`reportbug-gtk` package)-----
# ----------------------------------------------------------
echo '--- Remove UI for reportbug (`reportbug-gtk` package)'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  apt_package_name='reportbug-gtk'
if status="$(dpkg-query -W --showformat='${db:Status-Status}' "$apt_package_name" 2>&1)" \
    && [ "$status" = installed ]; then
  echo "\"$apt_package_name\" is installed and will be uninstalled."
  sudo apt-get purge -y "$apt_package_name"
else
  echo "Skipping, no action needed, \"$apt_package_name\" is not installed."
fi
fi

# ----------------------------------------------------------
# -------------Clear system crash report files--------------
# ----------------------------------------------------------
echo '--- Clear system crash report files'
sudo rm -rfv /var/crash/*
sudo rm -rfv /var/lib/systemd/coredump/
# ----------------------------------------------------------

# ----------------------------------------------------------
# --------------Clear system logs (`journald`)--------------
# ----------------------------------------------------------
echo '--- Clear system logs (`journald`)'
if ! command -v 'journalctl' &> /dev/null; then
  echo 'Skipping because "journalctl" is not found.'
else
  sudo journalctl --vacuum-time=1s
fi
sudo rm -rfv /run/log/journal/*
sudo rm -rfv /var/log/journal/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# -----------Clear Zeitgeist data (activity logs)-----------
# ----------------------------------------------------------
echo '--- Clear Zeitgeist data (activity logs)'
sudo rm -rfv {/root,/home/*}/.local/share/zeitgeist
# ----------------------------------------------------------

# ----------------------------------------------------------
# ---------------Clear obsolete APT packages----------------
# ----------------------------------------------------------
echo '--- Clear obsolete APT packages'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  sudo apt-get autoclean
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# ---------------Clear APT package file lists---------------
# ----------------------------------------------------------
echo '--- Clear APT package file lists'
sudo rm -rfv /var/lib/apt/lists/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# ---------Clear orphaned APT package dependencies----------
# ----------------------------------------------------------
echo '--- Clear orphaned APT package dependencies'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  sudo apt-get -y autoremove --purge
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# ---------------Clear cache for APT packages---------------
# ----------------------------------------------------------
echo '--- Clear cache for APT packages'
if ! command -v 'apt-get' &> /dev/null; then
  echo 'Skipping because "apt-get" is not found.'
else
  sudo apt-get clean
fi
# ----------------------------------------------------------

# ----------------------------------------------------------
# -----------------Clear system-wide cache------------------
# ----------------------------------------------------------
echo '--- Clear system-wide cache'
rm -rf /var/cache/*
# ----------------------------------------------------------


# ----------------------------------------------------------
# ----------------Clear user-specific cache-----------------
# ----------------------------------------------------------
echo '--- Clear user-specific cache'
rm -rfv ~/.cache/*
sudo rm -rfv root/.cache/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# --------------Clear thumbnails (icon cache)---------------
# ----------------------------------------------------------
echo '--- Clear thumbnails (icon cache)'
rm -rfv ~/.thumbnails/*
rm -rfv ~/.cache/thumbnails/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# --------------Clear global temporary folders--------------
# ----------------------------------------------------------
echo '--- Clear global temporary folders'
sudo rm -rfv /tmp/*
sudo rm -rfv /var/tmp/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# --------------------Clear screenshots---------------------
# ----------------------------------------------------------
echo '--- Clear screenshots'
# Clear default directory for GNOME screenshots
rm -rfv ~/Pictures/Screenshots/*
if [ -d ~/Pictures ]; then
  # Clear Ubuntu screenshots
  find ~/Pictures -name 'Screenshot from *.png' | while read -r file_path; do
    rm -fv "$file_path" # E.g. Screenshot from 2022-08-20 02-46-41.png
  done
  # Clear KDE (Spectatle) screenshots
  find ~/Pictures -name 'Screenshot_*' | while read -r file_path; do
    rm -fv "$file_path" # E.g. Screenshot_20220927_205646.png
  done
fi
# Clear ksnip screenshots
find ~ -name 'ksnip_*' | while read -r file_path; do
  rm -fv "$file_path" # E.g. ksnip_20220927-195151.png
done
# ----------------------------------------------------------

# ----------------------------------------------------------
# -----------------------Empty trash------------------------
# ----------------------------------------------------------
echo '--- Empty trash'
# Empty global trash
rm -rfv ~/.local/share/Trash/*
sudo rm -rfv /root/.local/share/Trash/*
# Empty Snap trash
rm -rfv ~/snap/*/*/.local/share/Trash/*
# Empty Flatpak trash (apps may not choose to use Portal API)
rm -rfv ~/.var/app/*/data/Trash/*
# ----------------------------------------------------------

# ----------------------------------------------------------
# ------------Clear GTK recently used files list------------
# ----------------------------------------------------------
echo '--- Clear GTK recently used files list'
# From global installations
rm -fv /.recently-used.xbel
rm -fv ~/.local/share/recently-used.xbel*
# From snap packages
rm -fv ~/snap/*/*/.local/share/recently-used.xbel
# From Flatpak packages
rm -fv ~/.var/app/*/data/recently-used.xbel
# ----------------------------------------------------------

# ----------------------------------------------------------
# ------------Clear privacy.sexy script history-------------
# ----------------------------------------------------------
echo '--- Clear privacy.sexy script history'
# Clear directory contents: "$HOME/.config/privacy.sexy/runs"
glob_pattern="$HOME/.config/privacy.sexy/runs/*"
rm -rfv $glob_pattern
# ----------------------------------------------------------

# ----------------------------------------------------------
# -------------Clear privacy.sexy activity logs-------------
# ----------------------------------------------------------
echo '--- Clear privacy.sexy activity logs'
# Clear directory contents: "$HOME/.config/privacy.sexy/logs"
glob_pattern="$HOME/.config/privacy.sexy/logs/*"
rm -rfv $glob_pattern
# ----------------------------------------------------------

# ----------------------------------------------------------
# -------------------Clear Python history-------------------
# ----------------------------------------------------------
echo '--- Clear Python history'
rm -fv ~/.python_history
sudo rm -fv /root/.python_history
# ----------------------------------------------------------

# ----------------------------------------------------------
# --------------------Clear bash history--------------------
# ----------------------------------------------------------
echo '--- Clear bash history'
rm -fv ~/.bash_history
sudo rm -fv /root/.bash_history
# ----------------------------------------------------------

echo 'Your privacy and security is now hardened 🎉💪'
echo 'Press any key to exit.'
read -n 1 -s
