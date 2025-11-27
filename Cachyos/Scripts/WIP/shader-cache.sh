#!/usr/bin/env bash
# shader_cache.sh - Clears Steam, games, GPU shader/log/crash caches on Linux
# Original author: AveYo
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

readonly XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Locate Steam installation
steam_root="${STEAM_ROOT:-$HOME/.steam/steam}"
[[ -d "$steam_root" ]] || steam_root="$HOME/.local/share/Steam"
[[ -d "$steam_root" ]] || {
    printf "Error: Steam installation not found\n" >&2
    exit 1
}

printf "Found Steam at: %s\n" "$steam_root"

# Define games to clean (appid -> exe:gamedir:mod)
declare -A games=(
    [730]="cs2:Counter-Strike Global Offensive:csgo"
)

# Kill Steam and related processes
readonly kill_procs=(steam steamwebhelper cs2)
printf "Stopping Steam processes...\n"
pkill -15 -x "${kill_procs[@]}" 2>/dev/null || :
sleep 1
pkill -9 -x "${kill_procs[@]}" 2>/dev/null || :
sleep 1

# Clean Steam logs and dumps
readonly logs=("$steam_root/logs" "$steam_root/dumps")
printf "Cleaning Steam logs and dumps...\n"
for dir in "${logs[@]}"; do
    if [[ -d "$dir" ]]; then
        find "$dir" -type f -exec truncate -s0 {} + 2>/dev/null || :
    fi
done

# Per-game: delete crashdumps and shader caches
printf "Cleaning game-specific caches...\n"
for appid in "${!games[@]}"; do
    IFS=':' read -r exe gamedir mod <<< "${games[$appid]}"
    game="$steam_root/steamapps/common/$gamedir"
    [[ -d "$game" ]] || continue

    printf "  Cleaning %s (appid: %s)...\n" "$gamedir" "$appid"

    # Crash dumps
    crashdir="$game/game/$mod"
    if [[ -d "$crashdir" ]]; then
        find "$crashdir" -type f -name '*.mdmp' -delete 2>/dev/null || :
    fi

    # Shader caches (multiple potential paths)
    shaders=(
        "$game/game/${mod}/shadercache"
        "$steam_root/steamapps/shadercache/${appid}"
    )
    for sdir in "${shaders[@]}"; do
        if [[ -d "$sdir" ]]; then
            find "$sdir" -type f -delete 2>/dev/null || :
        fi
    done
done

# Clean GPU-specific cache locations
printf "Cleaning GPU caches...\n"
readonly gpu_dirs=(
    "$XDG_CACHE_HOME/nv"
    "$XDG_CACHE_HOME/NVIDIA"
    "$XDG_CACHE_HOME/nvidia"
    "$XDG_CACHE_HOME/AMD"
    "$XDG_CACHE_HOME/amd"
    "$XDG_CACHE_HOME/Intel"
    "$HOME/.cache/NVIDIA/GLCache"
    "$HOME/.cache/NVIDIA/DXCache"
    "$HOME/.cache/NVIDIA/OptixCache"
    "$HOME/.cache/AMD/DxCache"
    "$HOME/.cache/AMD/DxcCache"
    "$HOME/.cache/AMD/GLCache"
    "$HOME/.cache/AMD/VkCache"
    "$HOME/.cache/Intel/ShaderCache"
    "$HOME/.nv"
    "$HOME/AMD"
    "$HOME/Intel"
)

for dir in "${gpu_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        find "$dir" -type f -delete 2>/dev/null || :
    fi
done

# NVIDIA ComputeCache (if present)
readonly nvcache="$HOME/.nv/ComputeCache"
if [[ -d "$nvcache" ]]; then
    printf "Cleaning NVIDIA ComputeCache...\n"
    find "$nvcache" -type f -delete 2>/dev/null || :
fi

printf "\nShader/log/crash cache cleanup complete!\n"
