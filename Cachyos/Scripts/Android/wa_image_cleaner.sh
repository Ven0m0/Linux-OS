#!/bin/bash

# WhatsApp media directory path
wa_dir="/data/data/com.termux/files/home/storage/shared/Android/media/com.whatsapp/WhatsApp/Media"

# Function to get directory size in MB
get_dir_size_mb() {
  if [[ -d $wa_dir ]]; then
    du -sm "$wa_dir" 2>/dev/null | cut -f1
  else
    echo 0
  fi
}

# Main script execution
echo "WhatsApp Media Cleanup Script"
echo "=============================="

# Get current directory size
current_size=$(get_dir_size_mb "wa_dir")
echo "Current WhatsApp media directory size: ${current_size}MB"

# Check if directory size exceeds 650MB
if [[ $current_size -gt 500 ]]; then
  echo "Directory size exceeds 500MB threshold. Starting cleanup..."
  find "$wa_dir" -iregex '.*\.\(jpg\|jpeg\|png\|gif\|mp4\|mov\|wmv\|flv\|webm\|mxf\|avi\|avchd\|mkv\)$' \
    -mtime +45 -print0 | xargs -0 rm -rf

  # Get new directory size after cleanup
  new_size=$(get_dir_size_mb "$wa_dir")
  freed_space=$((current_size - new_size))

  echo ""
  echo "Cleanup completed!"
  echo "Previous size: ${current_size}MB"
  echo "Current size: ${new_size}MB"
  echo "Space freed: ${freed_space}MB"

else
  echo "Directory size (${current_size}MB) is within the 650MB threshold. No cleanup needed."
fi

echo "Script execution completed."
