#!/bin/bash
DIR="$HOME/.cargo/bin"

for file in "$DIR"/*; do
  if [ -f "$file" ]; then
    rust-strip -s "$file" && echo "stripped $file"
  fi
done

read -s -r -p "✅Stripping rust apps done. Press Enter to exit..."
