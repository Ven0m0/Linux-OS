#!/bin/bash
set -euo pipefail

# Debug
set -x

echo "[*] Starting Minecraft mod and GeyserConnect update..."

# ─── Ferium Mod Update ─────────────────────────────────────────────────────────
echo "[*] Running ferium scan and upgrade..."
ferium scan && ferium upgrade

# ─── Clean .old Mods Folder ────────────────────────────────────────────────────
if [[ -d mods/.old ]]; then
    echo "[*] Cleaning old mod backups..."
    rm -f mods/.old/*
else
    echo "[*] Skipping cleanup: mods/.old does not exist."
fi

# ─── Repack Mods ───────────────────────────────────────────────────────────────
timestamp=$(date +%Y-%m-%d_%H-%M)
mods_src="$HOME/Documents/MC/Minecraft/mods"
mods_dst="$HOME/Documents/MC/Minecraft/mods-$timestamp"
config="$HOME/mc-repack.toml"

echo "[*] Repacking mods to: $mods_dst"
mc-repack jars -c "$config" --in "$mods_src" --out "$mods_dst"

# ─── Download GeyserConnect ────────────────────────────────────────────────────
echo "[*] Downloading latest GeyserConnect..."
curlopts=(-fsSL -Z --parallel-immediate --ca-native --compressed --compressed-ssh --http3 --http2)

URL="https://download.geysermc.org/v2/projects/geyserconnect/versions/latest/builds/latest/downloads/geyserconnect"
dest_dir="$HOME/Documents/MC/Minecraft/config/Geyser-Fabric/extensions"
tmp_jar="$dest_dir/GeyserConnect2.jar"
final_jar="$dest_dir/GeyserConnect.jar"

mkdir -p "$dest_dir"

if curl "${curlopts[@]}" -o "$tmp_jar" "$URL"; then
    echo "[*] Download complete: $tmp_jar"
else
    echo "[!] Failed to download GeyserConnect!" >&2
    exit 1
fi

# ─── Backup Existing JAR ───────────────────────────────────────────────────────
if [[ -f "$final_jar" ]]; then
    echo "[*] Backing up existing GeyserConnect.jar..."
    mv "$final_jar" "$final_jar.bak"
fi

# ─── Repack and Cleanup ────────────────────────────────────────────────────────
echo "[*] Repacking GeyserConnect..."
mc-repack jars -c "$config" --in "$tmp_jar" --out "$final_jar"
rm -f "$tmp_jar"
echo "[✔] GeyserConnect updated and cleaned up."

echo "[✅] Minecraft update process complete."
