#!/usr/bin/env bash
# optimize-local-fonts.sh
# Optimizes local TTF/OTF fonts to reduce file size.
# Usage: optimize_local_fonts <file_or_dir> [horiz_scale]

optimize_local_fonts(){
  local target="${1:?Provide font file or directory}"
  local scale="${2:-1.0}"   # horizontal scale (default 1.0 = no scaling)

  # Find font files, handling cases where no matches are found.
  shopt -s nullglob
  local fonts=()
  if [ -d "$target" ]; then
    fonts=("$target"/*.ttf "$target"/*.otf)
  elif [ -f "$target" ]; then
    fonts=("$target")
  else
    echo "Error: Invalid file or directory: $target" >&2
    return 1
  fi

  if [ ${#fonts[@]} -eq 0 ]; then
    echo "No.ttf or.otf fonts found in '$target'"
    return 0
  fi

  for font in "${fonts[@]}"; do
    [ -f "$font" ] |

| continue
    echo "Processing: $font"
    local base="${font%.*}"
    local tmp="${base}-tmp.ttf"
    local out="${base}-Optimized.ttf"

    cp "$font" "$tmp"

    # 1. Optional horizontal scaling via TTX (XML representation)
    if (( $(echo "$scale < 1.0" | bc -l) )); then
      echo "  Scaling horizontally by a factor of $scale..."
      local ttx_file="${tmp%.ttf}.ttx"
      ttx -o "$ttx_file" "$tmp"
      # Modify advanceWidth values in the XML file
      perl -pi -e "s/(<advanceWidth value=\")(\d+)(\")/\$1. int(\$2 * $scale). \$3/e" "$ttx_file"
      ttx -o "$tmp" "$ttx_file"
      rm "$ttx_file"
    fi

    # 2. Optimize layout tables using the fontTools Python library
    echo "  Optimizing layout tables..."
    python3 - <<EOF
from fontTools import ttLib, otlLib
import sys

try:
    font = ttLib.TTFont("$tmp")
    otlLib.optimize(font)
    font.save("$out")
except Exception as e:
    print(f"  Error processing font with Python: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    # Check if the Python script executed successfully
    if [ $? -ne 0 ]; then
      echo "  Failed to optimize $font. Skipping."
      rm "$tmp"
      continue
    fi

    rm "$tmp"
    echo "→ Optimized font saved to: $out"
  done
}

# Example usage:
# To optimize all fonts in a directory named 'my-fonts':
# optimize_local_fonts./my-fonts

# To optimize and condense fonts by 5% in that directory:
# optimize_local_fonts./my-fonts 0.95
