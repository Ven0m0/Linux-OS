#!/bin/bash
DIR="$HOME/.cargo/bin"

for file in "$DIR"/*; do
  if [ -f "$file" ]; then
    rust-strip -s "$file" && echo "stripped $file"
  fi
done
