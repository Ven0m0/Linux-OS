#!/usr/bin/env bash
# System cleaning functions library
# Contains shared functions for cleaning various system caches, logs, and temporary files

# Clean APT package manager cache
# Removes cached package files and orphaned packages
clean_apt_cache() {
  sudo apt-get clean -yq
  sudo apt-get autoclean -yq
  sudo apt-get autoremove --purge -yq
}

# Clean system cache directories
# Removes temporary files and user/root caches
clean_cache_dirs() {
  sudo rm -rf /tmp/* 2>/dev/null || :
  sudo rm -rf /var/tmp/* 2>/dev/null || :
  sudo rm -rf /var/cache/* 2>/dev/null || :
  rm -rf ~/.cache/* 2>/dev/null || :
  sudo rm -rf /root/.cache/* 2>/dev/null || :
  rm -rf ~/.thumbnails/* 2>/dev/null || :
  rm -rf ~/.cache/thumbnails/* 2>/dev/null || :
}

# Clean shell and Python history files
# Removes bash and Python history for current user and root
clean_history_files() {
  rm -f ~/.python_history 2>/dev/null || :
  sudo rm -f /root/.python_history 2>/dev/null || :
  rm -f ~/.bash_history 2>/dev/null || :
  sudo rm -f /root/.bash_history 2>/dev/null || :
  history -c 2>/dev/null || :
}

# Clean crash dumps and core dumps
# Removes system crash reports
clean_crash_dumps() {
  sudo rm -rf /var/crash/* 2>/dev/null || :
  sudo rm -rf /var/lib/systemd/coredump/* 2>/dev/null || :
}

# Clean systemd journal logs
# Reduces journal size and removes old log files
clean_journal_logs() {
  sudo journalctl --rotate --vacuum-size=1 --flush --sync -q 2>/dev/null || :
  sudo rm -rf --preserve-root -- /run/log/journal/* /var/log/journal/* 2>/dev/null || :
  sudo systemd-tmpfiles --clean 2>/dev/null || :
}

# Empty trash directories
# Clears trash for user, root, and snap/flatpak applications
clean_trash() {
  rm -rf ~/.local/share/Trash/* 2>/dev/null || :
  sudo rm -rf /root/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/snap/*/*/.local/share/Trash/* 2>/dev/null || :
  rm -rf ~/.var/app/*/data/Trash/* 2>/dev/null || :
}

# Clean Docker resources
# Removes unused Docker containers, images, volumes, and build cache
clean_docker() {
  if command -v docker &>/dev/null; then
    sudo docker system prune -af --volumes 2>/dev/null || :
    sudo docker container prune -f 2>/dev/null || :
    sudo docker image prune -af 2>/dev/null || :
    sudo docker volume prune -f 2>/dev/null || :
    sudo docker builder prune -af 2>/dev/null || :
  fi
}

# Clean npm cache
# Removes npm cache directory
clean_npm_cache() {
  if has npm; then
    npm cache clean --force 2>/dev/null || :
  fi
}

# Clean pip cache
# Removes Python pip cache
clean_pip_cache() {
  if command -v pip &>/dev/null; then
    pip cache purge 2>/dev/null || :
  fi
  if command -v pip3 &>/dev/null; then
    pip3 cache purge 2>/dev/null || :
  fi
}

# Run all basic cleaning functions
# Executes a comprehensive system cleanup
clean_all_basic() {
  clean_apt_cache
  clean_cache_dirs
  clean_history_files
  clean_crash_dumps
  clean_journal_logs
  clean_trash
}

# Run comprehensive cleanup including optional services
# Executes all available cleaning functions
clean_all_comprehensive() {
  clean_apt_cache
  clean_cache_dirs
  clean_history_files
  clean_crash_dumps
  clean_journal_logs
  clean_trash
  clean_docker
  clean_npm_cache
  clean_pip_cache
}

# Remove system documentation files
# Removes man pages, docs, locales (except en_GB), and related files
clean_documentation() {
  echo "Removing documentation files..."
  find /usr/share/doc/ -depth -type f ! -name copyright -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.gz' -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.pdf' -delete 2>/dev/null || :
  find /usr/share/doc/ -name '*.tex' -delete 2>/dev/null || :
  find /usr/share/doc/ -type d -empty -delete 2>/dev/null || :

  echo "Removing man pages and related files..."
  sudo rm -rf /usr/share/groff/* /usr/share/info/* /usr/share/lintian/* \
    /usr/share/linda/* /var/cache/man/* /usr/share/man/* 2>/dev/null || :
}

# Configure dpkg to exclude documentation and locales
# Sets up dpkg to not install docs/man pages in future package installations
configure_dpkg_nodoc() {
  local dpkg_config='path-exclude /usr/share/doc/*
path-exclude /usr/share/help/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
# we need to keep copyright files for legal reasons
path-include /usr/share/doc/*/copyright'

  echo "$dpkg_config" | sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc >/dev/null
  echo "Configured dpkg to exclude documentation in future installations"
}
