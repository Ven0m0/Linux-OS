#!/usr/bin/env bash
set -euo pipefail

sudo -v
sudo keyserver-rank --yes

declare -A LIST=(
  [arch]="/etc/pacman.d/mirrorlist"
  [chaotic-aur]="/etc/pacman.d/chaotic-mirrorlist"
  [cachyos]="/etc/pacman.d/cachyos-mirrorlist"
)

cleanup() {
  [[ -n "${tmp:-}" && -f "$tmp" ]] && rm -f "$tmp"
}
trap cleanup EXIT

for repo in "${!LIST[@]}"; do
  dest="${LIST[$repo]}"
  tmp=$(mktemp)

sudo rate-mirrors \
    --save="$tmp" \
    "$repo" \
    --fetch-mirrors-timeout=300000 \
    --completion=1 \
    --max-delay=10000 \
    --entry-country=DE \
    --allow-root

  sudo mv "$dest" "${dest}.backup.$(date +%Y%m%d_%H%M)"
  sudo mv "$tmp" "$dest"

  echo "✔ $repo → updated mirrorlist at $dest"
done
