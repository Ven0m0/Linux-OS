#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# cd-prep.sh: Convert high-res audio to Red Book (16bit/44.1kHz) with high-quality dithering
# Usage: ./cd-prep.sh /path/to/music_folder
set -euo pipefail; shopt -s nullglob
LC_ALL=C
INPUT_DIR="${1:-.}"
OUTPUT_DIR="cd_ready"
mkdir -p "$OUTPUT_DIR"
msg() { printf '\033[1;34m[OPT]\033[0m %s\n' "$@"; }
# Check for ffmpeg
command -v ffmpeg &>/dev/null || { echo "Install ffmpeg first."; exit 1; }

msg "Scanning $INPUT_DIR for audio..."
for f in "$INPUT_DIR"/*.{flac,wav,m4a,mp3}; do
  filename=$(basename "$f")
  base="${filename%.*}"
  # FFmpeg Filter Chain Explanation:
  # 1. aresample=44100:resampler=soxr : Use SoX Resampler library (best in class)
  # 2. osf=s16 : Output Sample Format = Signed 16-bit
  # 3. dither_method=triangular : Best general-purpose dither for car audio (noise shaping can be weird in loud cars)
  msg "Processing: $filename"
  ffmpeg -y -i "$f" \
    -af "aresample=44100:resampler=soxr:precision=28:dither_method=triangular" \
    -c:a pcm_s16le "$OUTPUT_DIR/$base.wav" -hide_banner -loglevel error
done
msg "Done. Burn files in '$OUTPUT_DIR' at 16x speed."
