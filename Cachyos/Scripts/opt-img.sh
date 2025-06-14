#!/bin/bash

# Directories to safely process (including your additions)
SAFE_DIRS=(
    "/usr/share/icons"
    "/usr/share/pixmaps"
    "/usr/share/themes"
    "/usr/local/share/icons"
    "/usr/local/share/pixmaps"
    "/usr/share/plasma/avatars"
    "/usr/share/plasma/look-and-feel"
    "/usr/share/sddm/flags"
    "/usr/share/sddm/faces"
    "/usr/share/sddm/themes"
    "/usr/share/wallpapers"
    "$HOME/.local/share/omf/docs"
)

BACKUP_DIR="$HOME/image_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

LOGFILE="$HOME/image_compression_log.txt"
echo "Image compression with backups started at $(date)" > "$LOGFILE"

compress_image() {
    local file="$1"

    # Backup the original file preserving directory structure
    local backup_path="$BACKUP_DIR$file"
    mkdir -p "$(dirname "$backup_path")"
    cp -p "$file" "$backup_path"

    case "${file,,}" in
        *.jpg|*.jpeg)
            jpegoptim --strip-all --all-progressive --quiet "$file" >> "$LOGFILE" 2>&1
            ;;
        *.png)
            optipng -o7 -strip all -quiet "$file" >> "$LOGFILE" 2>&1
            ;;
        *.gif)
            gifsicle -O3 --batch --threads=16 "$file" >> "$LOGFILE" 2>&1
            ;;
        *.svg)
            svgo --multipass --quiet "$file" >> "$LOGFILE" 2>&1
            scour -i "$file" -o "$file.tmp" --enable-id-stripping --enable-comment-stripping >> "$LOGFILE" 2>&1
            mv "$file.tmp" "$file"
            ;;
        *.webp)
            cwebp -lossless -q 100 "$file" -o "$file.tmp" && mv "$file.tmp" "$file" >> "$LOGFILE" 2>&1
            ;;
        *.avif)
            avifenc --min 0 --max 0 --speed 8 "$file" "$file.tmp" && mv "$file.tmp" "$file" >> "$LOGFILE" 2>&1
            ;;
        *.jxl)
            cjxl "$file" "$file.tmp" --lossless_jpeg=1 && mv "$file.tmp" "$file" >> "$LOGFILE" 2>&1
            ;;
    esac
}

for dir in "${SAFE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
            -iname "*.svg" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.jxl" \
        \) | while read -r img; do
            echo "Compressing: $img" >> "$LOGFILE"
            compress_image "$img"
        done
    fi
done

echo "Compression finished at $(date)" >> "$LOGFILE"
echo "Backups saved in: $BACKUP_DIR"
echo "Done. See log: $LOGFILE"
