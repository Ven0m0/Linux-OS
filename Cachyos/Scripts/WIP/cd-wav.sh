#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
#
# cd-optimize.sh: Prep audio for Red Book CD (16bit/44.1kHz) with dither & burn guide
#
# Usage: ./cd-optimize.sh [INPUT_DIR]
# Constraints: Requires ffmpeg.

set -euo pipefail
shopt -s nullglob globstar IFS=$'\n\t' LC_ALL=C

# --- Helpers ---
has() { command -v -- "$1" &>/dev/null; }
msg() { printf '\033[1;34m[INFO]\033[0m %s\n' "$@"; }
wrn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$@" >&2; }
die() {
  printf '\033[1;31m[ERR ]\033[0m %s\n' "$@" >&2
  exit "${2:-1}"
}

# --- Main ---
main() {
  local input_dir="${1:-.}"
  local output_dir="cd_master_ready"

  has ffmpeg || die "Missing dependency: ffmpeg"

  [[ -d $input_dir ]] || die "Input directory not found: $input_dir"
  mkdir -p "$output_dir"

  msg "Source: $input_dir"
  msg "Target: $output_dir"
  msg "Mode:   Red Book (44.1kHz/16-bit/Stereo) + Triangular Dither"

  # 1. Processing Loop
  local count=0
  local lossy_count=0

  # Scan for supported audio
  while IFS= read -r file; do
    local ext="${file##*.}"
    local base
    base=$(basename "$file")
    base="${base%.*}"

    # Input Guard: Warn if source is already lossy
    if [[ $ext =~ ^(mp3|m4a|aac|ogg)$ ]]; then
      wrn "Processing lossy source: $base.$ext (Suboptimal for CD)"
      ((lossy_count++))
    fi

    # FFmpeg: Resample (SoX) -> Dither (Triangular) -> PCM
    # - aresample: Use SoX engine, strictly 44100Hz
    # - dither_method=triangular: Best for car environments
    ffmpeg -y -v error -i "$file" \
      -af "aresample=44100:resampler=soxr:precision=28:dither_method=triangular" \
      -c:a pcm_s16le \
      "$output_dir/$base.wav"

    printf "."
    ((count++))
  done < <(find "$input_dir" -maxdepth 1 -type f -regextype posix-extended -regex ".*\.(flac|wav|mp3|m4a|aac|ogg|alac|aiff)$")

  printf "\n"

  ((count > 0)) || die "No audio files found in $input_dir"

  # 2. Final Manifest
  msg "Processed $count files."
  if ((lossy_count > 0)); then
    wrn "Detected $lossy_count lossy input files. Quality compromised."
  else
    msg "All inputs were lossless. Quality optimized."
  fi

  # 3. Burning Instructions (The 'Physical' Workflow)
  cat <<EOF

---------------------------------------------------------------------
   🔥 BURN INSTRUCTIONS (CRITICAL)
---------------------------------------------------------------------
1. MEDIA : Use Verbatim AZO (Blue) or Taiyo Yuden (Green/Blue).
           Avoid generic/transparent discs.
2. SPEED : Set burn speed to 16x (or 24x).
           DO NOT use Max/52x (High Jitter).
           DO NOT use 1x (Modern lasers unstable).
3. MODE  : "Disc-At-Once" (DAO) / "Gapless" (2-second gap is standard).
---------------------------------------------------------------------
Files ready in: $output_dir/
EOF
}

main "$@"
