#!/usr/bin/env bash
# AveYo: shader_cache.sh | clears Steam, games, GPU shader/log/crash caches on Linux
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

steam_root="${STEAM_ROOT:-$HOME/.steam/steam}"
[[ -d "$steam_root" ]] || steam_root="$HOME/.local/share/Steam"
[[ -d "$steam_root" ]] || {
  printf "Steam not found\n" >&2
  exit 1
}

declare -A games=(
  [730]="cs2:Counter-Strike Global Offensive:csgo"
)

kill_procs=(steam steamwebhelper cs2)
pkill -15 -x "${kill_procs[@]}" || :
sleep 1
pkill -9 -x "${kill_procs[@]}" || :
sleep 1

logs=("$steam_root/logs" "$steam_root/dumps")
for dir in "${logs[@]}"; do
  [[ -d "$dir" ]] && find "$dir" -type f -exec truncate -s0 {} +
done
# Per-game: delete crashdumps, shader cache
for appid in "${!games[@]}"; do
  IFS=':' read -r exe gamedir mod <<< "${games[$appid]}"
  game="$steam_root/steamapps/common/$gamedir"
  [[ -d "$game" ]] || continue
  # Crash dumps
  crashdir="$game/game/$mod"
  [[ -d "$crashdir" ]] && find "$crashdir" -type f -name '*.mdmp' -delete || :
  # Shader caches (multiple potential paths)
  shaders=(
    "$game/game/${mod}/shadercache"
    "$steam_root/steamapps/shadercache/${appid}"
  )
  for sdir in "${shaders[@]}"; do
    [[ -d "$sdir" ]] && find "$sdir" -type f -delete || :
  done
done

# Common GPU cache locations
gpu_dirs=(
  "$XDG_CACHE_HOME/nv" "$XDG_CACHE_HOME/NVIDIA" "$XDG_CACHE_HOME/nvidia"
  "$XDG_CACHE_HOME/AMD" "$XDG_CACHE_HOME/amd" "$XDG_CACHE_HOME/Intel"
  "$HOME/.cache/NVIDIA/GLCache"
  "$HOME/.cache/NVIDIA/DXCache"
  "$HOME/.cache/NVIDIA/OptixCache"
  "$HOME/.cache/AMD/DxCache"
  "$HOME/.cache/AMD/DxcCache"
  "$HOME/.cache/AMD/GLCache"
  "$HOME/.cache/AMD/VkCache"
  "$HOME/.cache/Intel/ShaderCache"
  "$HOME/.nv" "$HOME/AMD" "$HOME/Intel"
)
for dir in "${gpu_dirs[@]}"; do
  [[ -d "$dir" ]] && find "$dir" -type f -delete || :
done

# NVIDIA ComputeCache (if present)
nvcache="$HOME/.nv/ComputeCache"
[[ -d "$nvcache" ]] && find "$nvcache" -type f -delete || :

printf "Shader/log/crash cache cleanup complete.\n"
