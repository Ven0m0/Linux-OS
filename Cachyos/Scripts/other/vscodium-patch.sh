#!/usr/bin/env bash
LC_ALL=C
# Set target path based on standard Arch package structure
readonly VSC_INSTALL_DIR="/usr/share/vscodium"
readonly PROD_JSON_PATH="${VSC_INSTALL_DIR}/resources/app/product.json"

# --- MS Marketplace Endpoints ---
# NOTE: These keys are derived from a standard VS Code product.json
# They must be in sync with the upstream endpoints.
# Array of key-value replacements for sed
# (Using double-quotes to allow for dynamic variable expansion)
# Using printf %s to handle newlines and ensure clean string output
ms_config=(
  '"extensionsGallery": {'
  '    "serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",'
  '    "itemUrl": "https://marketplace.visualstudio.com/items",'
  '    "resourceUrlTemplate": "https://{publisher}.gallerycdn.vsassets.io/extensions/{publisher}/{extension}/{version}/vsc-extension",'
  '    "controlUrl": "https://v1.gallery.vsassets.io/gallery/publisher",'
  '    "recommendationsUrl": "https://vscodeinsiders.blob.core.windows.net/gallery/index"'
  '}'
  '"extensionEnabledApiProposals": {}'
  '"linkProtectionTrustedDomains": [ "marketplace.visualstudio.com" ]'
)
ms_config_str=$(printf '%s\n' "${ms_config[@]}")

fn_enable_ms_marketplace() {
  local -r target_file="${1}"
  local -r temp_file="${target_file}.tmp.$$"
  local -r ms_endpoints="${2}"
  local ret=0

  if [[ ! -f $target_file ]]; then
    printf "Error: VSCodium product.json not found at %s\n" "$target_file" >&2
    return 1
  fi

  # Use grep/sed to replace the 'extensionsGallery' block
  # This targets the start of the block set by VSCodium's build scripts
  # It preserves the rest of the product.json structure.

  # Read the product.json, substitute the Open VSX block with the MS block,
  # and save to a temp file.
  if ! sed '/"extensionsGallery": {/,/}/ {
    /"extensionsGallery": {/!d;
    r /dev/stdin
  }' "$target_file" <<<"$ms_endpoints" >"$temp_file" 2>/dev/null; then
    ret=1
  fi

  # Atomically replace the original file
  if [[ ${ret} -eq 0 ]] && mv -f "$temp_file" "$target_file" 2>/dev/null; then
    printf "Success. VSCodium now uses MS Marketplace. Remember to re-run this after updates.\n"
  else
    printf "Error: Failed to patch or replace %s. (Permissions?)\n" "$target_file" >&2
    ret=1
  fi

  rm -f "$temp_file" 2>/dev/null || :
  return "$ret"
}

# Execute the function
# The command must be run with sufficient permissions (e.g., sudo)
# to modify the file in /usr/share.
# Example: sudo fn_enable_ms_marketplace "${PROD_JSON_PATH}" "${ms_config_str}"

# Or, if you want to be extremely precise about your target installation:
ret=$(fn_enable_ms_marketplace "$PROD_JSON_PATH" "$ms_config_str")

# Check return status for blunt, factual reporting
if [[ $? -ne 0 ]]; then
  printf "ERROR: Failed to apply MS Marketplace patch.\n" >&2
fi
