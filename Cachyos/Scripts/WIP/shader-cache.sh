#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

# 1. Setup Directories
readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
readonly XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

# Detect Steam Path (Standard vs Flatpak vs Custom)
if [[ -d "${HOME}/.steam/steam" ]]; then
  steam_root="${HOME}/.steam/steam"
elif [[ -d "$XDG_DATA_HOME/Steam" ]]; then
  steam_root="$XDG_DATA_HOME/Steam"
else
  printf "Error: Steam installation not found.\n" >&2
  exit 1
fi
printf "Found Steam at: %s\n" "$steam_root"
# 2. Define Games (AppID -> ProcessName:Directory:ModPath)
# Added safeguards to only clean if directory exists
declare -A games=(
  [730]="cs2:Counter-Strike Global Offensive:csgo"
)

# 3. Robust Process Killer
readonly kill_procs=(steam steamwebhelper cs2)
printf "Stopping Steam processes...\n"
# Soft kill first
pkill -15 -x "${kill_procs[@]}" 2> /dev/null || true
# Wait up to 5 seconds for them to exit gracefully
for i in {1..10}; do
  if ! pgrep -x "${kill_procs[@]}" > /dev/null; then
    break
  fi
  sleep 0.5
done
# Force kill anything remaining
pkill -9 -x "${kill_procs[@]}" 2> /dev/null || true
printf "Steam stopped.\n"
# 4. Clean Steam Logs (Faster method)
# Using> file is faster than find+truncate for single files,
# but for directories of logs, rm is cleanest.
readonly logs=("$steam_root/logs" "$steam_root/dumps")
printf "Cleaning Steam logs...\n"
for dir in "${logs[@]}"; do
  if [[ -d "$dir" ]]; then
    # Safely remove all files inside, keeping the directory
    rm -f "${dir:?}"/* 2> /dev/null || true
  fi
done
# 5. Clean Game Specific Caches
printf "Cleaning game caches...\n"
for appid in "${!games[@]}"; do
  IFS=':' read -r exe gamedir mod <<< "${games[$appid]}"
  game_path="$steam_root/steamapps/common/$gamedir"
  [[ -d "$game_path" ]] || continue
  printf "  -> Cleaning %s (%s)...\n" "$gamedir" "$appid"
  # Crash Dumps (.mdmp files only)
  # Use find here as we only want specific extensions
  find "$game_path" -type f -name "*.mdmp" -delete 2> /dev/null || true
  # Shader Cache Folders (Safe to rm -rf content)
  target_dirs=(
    "$game_path/game/$mod/shadercache"
    "$steam_root/steamapps/shadercache/$appid"
  )
  for t_dir in "${target_dirs[@]}"; do
    if [[ -d "$t_dir" ]]; then
      rm -rf "${t_dir:?}"/* 2> /dev/null || true
    fi
  done
done
# 6. Clean GPU Caches (The big optimization)
printf "Cleaning GPU caches...\n"
# List of folders safe to completely empty
readonly gpu_cache_dirs=(
  # MESA (AMD RADV / Intel ANV - Most important for Linux)
  "${XDG_CACHE_HOME}/mesa_shader_cache"
  # NVIDIA (Modern)
  "${XDG_CACHE_HOME}/nvidia/GLCache"
  "${XDG_CACHE_HOME}/nvidia/DXCache"
  "${XDG_CACHE_HOME}/nvidia/OptixCache"
  # NVIDIA (Legacy)
  "${HOME}/.nv/ComputeCache"
  "${HOME}/.nv/GLCache"
  # AMD (Proprietary/Pro)
  "${XDG_CACHE_HOME}/AMD/DxCache"
  "${XDG_CACHE_HOME}/AMD/GLCache"
  "${XDG_CACHE_HOME}/AMD/VkCache"
  # Intel (Proprietary)
  "${XDG_CACHE_HOME}/Intel/ShaderCache"
  # Microsoft / DXVK
  "${XDG_CACHE_HOME}/dxvk-cache"
)
for dir in "${gpu_cache_dirs[@]}"; do
  if [[ -d "$dir" ]]; then
    printf "  -> Purging %s\n" "${dir##*/}" # Print folder name only
    # rm -rf is 100x faster than find -delete for caches with 10k+ files
    rm -rf "${dir:?}"/* 2> /dev/null || true
  fi
done
printf "\n\033[32mCleanup complete!\033[0m\n"
