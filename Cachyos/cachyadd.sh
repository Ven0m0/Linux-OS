#!/usr/bin/env bash
# Add cachyos repo's to your existing arch install automatically
# https://wiki.cachyos.org/features/optimized_repos/
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -O && {
  tar xvf cachyos-repo.tar.xz \
    && cd cachyos-repo || exit
  chmod +x cachyos-repo.sh \
    && sudo ./cachyos-repo.sh
}
