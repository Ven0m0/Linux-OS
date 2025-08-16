#!/usr/bin/env bash

set -euo pipefail

cd "$HOME/.dotfiles" || exit
git pull --rebase --autostash
echo 'Done! 👯‍'
