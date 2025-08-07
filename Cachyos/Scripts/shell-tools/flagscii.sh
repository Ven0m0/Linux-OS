#!/usr/bin/env bash

# Trans flag colors (ANSI 256 color escape codes for better accuracy)
colors=(
  $'\033[38;5;117m'  # Light Blue
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;15m'   # White
  $'\033[38;5;218m'  # Pink
  $'\033[38;5;117m'  # Light Blue
)

reset=$'\033[0m'

# Read banner into array
read -r -d '' -a banner <<'EOF'
██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗███████╗
██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██╔════╝
██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  ███████╗
██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  ╚════██║
╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗███████║
 ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝
EOF

# Total lines
lines=${#banner[@]}

# Loop through each line and apply scaled trans flag colors
for i in "${!banner[@]}"; do
  # Map line index to color index (scaled to 5 colors)
  color_index=$(( i * 5 / lines ))
  printf "%s%s%s\n" "${colors[color_index]}" "${banner[i]}" "$reset"
done
