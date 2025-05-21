#!/usr/bin/env bash
set -euo pipefail

sudo keyserver-rank --yes
sudo cachyos-rate-mirrors

echo "✔ Updated mirrorlists"
