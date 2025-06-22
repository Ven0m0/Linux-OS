#!/bin/bash

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
    local lower_file="${file,,}"

    # Backup original file preserving directory structure
    local backup_path="$BACKUP_DIR$file"
    mkdir -p "$(dirname "$backup_path")"
    cp -p -- "$file" "$backup_path"

    local tmpfile

    case "$lower_file" in
        *.jpg|*.jpeg)
            jpegoptim --strip-all --all-progressive --quiet -- "$file" >> "$LOGFILE" 2>&1
            ;;
        *.png)
            tmpfile=$(mktemp --suffix=.png)
            if pngquant --strip --quality=60-85 --speed=1 --output "$tmpfile" -- "$file" >> "$LOGFILE" 2>&1; then
                oxipng -o max --strip all -a -i 0 --force -Z --zi 20 --out "$file" "$tmpfile" >> "$LOGFILE" 2>&1
                rm -f -- "$tmpfile"
            else
                echo "pngquant failed, using oxipng only on $file" >> "$LOGFILE"
                oxipng -o max --strip all -a -i 0 --force -Z --zi 20 -- "$file" >> "$LOGFILE" 2>&1
                rm -f -- "$tmpfile"
            fi
            ;;
        *.gif)
            gifsicle -O3 --batch --threads=16 -- "$file" >> "$LOGFILE" 2>&1
            ;;
        *.svg)
            svgo --multipass --quiet -- "$file" >> "$LOGFILE" 2>&1
            scour -i "$file" -o "$file.tmp" --enable-id-stripping --enable-comment-stripping >> "$LOGFILE" 2>&1
            mv -f -- "$file.tmp" "$file"
            ;;
        *.webp)
            tmpfile=$(mktemp --suffix=.webp)
            if cwebp -lossless -q 100 -- "$file" -o "$tmpfile" >> "$LOGFILE" 2>&1; then
                mv -f -- "$tmpfile" "$file"
            else
                rm -f -- "$tmpfile"
            fi
            ;;
        *.avif)
            tmpfile=$(mktemp --suffix=.avif)
            if avifenc --min 0 --max 0 --speed 8 -- "$file" "$tmpfile" >> "$LOGFILE" 2>&1; then
                mv -f -- "$tmpfile" "$file"
            else
                rm -f -- "$tmpfile"
            fi
            ;;
        *.jxl)
            tmpfile=$(mktemp --suffix=.jxl)
            if cjxl --lossless_jpeg=1 -- "$file" "$tmpfile" >> "$LOGFILE" 2>&1; then
                mv -f -- "$tmpfile" "$file"
            else
                rm -f -- "$tmpfile"
            fi
            ;;
        *.html|*.htm)
            minhtml --allow-removing-spaces-between-attributes --allow-optimal-entities --allow-noncompliant-unquoted-attribute-values --minify-doctype --in-place -- "$file" >> "$LOGFILE" 2>&1 || echo "minhtml failed on $file" >> "$LOGFILE"
            ;;
        *.css)
            minhtml --in-place --minify-css -- "$file" >> "$LOGFILE" 2>&1 || echo "minhtml failed on $file" >> "$LOGFILE"
            ;;
        *.js)
            minhtml --in-place --minify-js -- "$file" >> "$LOGFILE" 2>&1 || echo "minhtml failed on $file" >> "$LOGFILE"
            ;;
        *)
            echo "Skipping unsupported file type: $file" >> "$LOGFILE"
            ;;
    esac
}

export -f compress_image
export BACKUP_DIR LOGFILE

JOBS=4

for dir in "${SAFE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        find "$dir" -type f \( \
            -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
            -iname "*.svg" -o -iname "*.webp" -o -iname "*.avif" -o -iname "*.jxl" -o \
            -iname "*.html" -o -iname "*.htm" -o -iname "*.css" -o -iname "*.js" \
        \) -print0 | xargs -0 -P "$JOBS" -I{} bash -c 'echo "Compressing: {}" >> "$LOGFILE"; compress_image "{}"'
    else
        echo "Directory $dir does not exist, skipping." >> "$LOGFILE"
    fi
done

echo "Compression finished at $(date)" >> "$LOGFILE"
echo "Backups saved in: $BACKUP_DIR"
echo "Done. See log: $LOGFILE"
