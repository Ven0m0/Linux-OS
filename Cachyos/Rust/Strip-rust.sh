#!/bin/bash
DIR="$HOME/.cargo/bin"

for file in "$DIR"/*; do
  if [ -f "$file" ]; then
    rust-strip -s -x "$file" && strip -s -x "$file" && llvm-strip -s -x -D "$file" && echo "stripped $file"
  fi
done

read -s -r -p "✅Stripping rust apps done. Press Enter to exit..."
