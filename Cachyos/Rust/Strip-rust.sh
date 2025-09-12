#!/usr/bin/env bash
DIR="${HOME}/.cargo/bin/"

LC_ALL=C find -O3 "$DIR" -maxdepth 1 -type f -executable -exec strip -sx {} +
