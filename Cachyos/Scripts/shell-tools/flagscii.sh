#!/usr/bin/env bash

# Trans flag colors (ANSI 256 color escape codes for better accuracy)
# You can replace with truecolor (24-bit) if supported: \033[38;2;R;G;Bm
colors=(
  $'\033[38;2;173;216;230m'  # Light Blue
  $'\033[38;2;255;192;203m'  # Pink
  $'\033[38;2;255;255;255m'  # White
  $'\033[38;2;255;192;203m'  # Pink
  $'\033[38;2;173;216;230m'  # Light Blue
)

  # Light blue
  # Pink
  # White

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
