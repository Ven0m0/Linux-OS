#!/bin/bash
LC_ALL=C

SED=$(command -v sd &>/dev/null && echo sd || echo sed)
JQ=$(command -v jaq &>/dev/null && echo jaq || echo jq)

dl(){
  local url="$1" out="$2"
  if command -v curl &>/dev/null; then
    curl -fSL -o "$out" "$url" || wget -q -O "$out" "$url"
  else
    wget -q -O "$out" "$url"
  fi
}

add_mime_type(){ ! grep -qE "^MimeType=.*\b${1};" "$2" && $SED -i -E "s#^(MimeType=.*;)\$#\1${1};#" "$2"; }
fix_15741(){ add_mime_type 'inode/directory' "$1"; }
fix_129953(){ $SED -i -E 's/"desktopName":\s*"(.+)-url-handler\.desktop"/"desktopName": "\1.desktop"/' "$1"; }
fix_214741(){ add_mime_type 'text/plain' "$1"; }

xdg_patch(){
  while read -r file; do
    case "$file" in
      *.desktop) fix_214741 "$file"; fix_15741 "$file"; echo "patched $file" ;;
      */package.json) fix_129953 "$file"; echo "patched $file" ;;
      *) echo "unexpected file: $file" ;;
    esac
  done
}

find_vscode_files(){
  ls /usr/lib/code*/package.json \
     /opt/visual-studio-code*/resources/app/package.json \
     /opt/vscodium*/resources/app/package.json \
     /usr/share/applications/code*.desktop \
     /usr/share/applications/vscode*.desktop \
     /usr/share/applications/vscodium*.desktop \
     2>/dev/null | grep -vE '\-url-handler.desktop$'
}

vscodium_marketplace(){
  local -r prod="${1:-/usr/share/vscodium/resources/app/product.json}"
  local -r revert="${2:-0}"
  [[ ! -f $prod ]] && printf "Error: %s not found\n" "$prod" >&2 && return 1

  if [[ $SED == "sd" ]]; then
    if [[ $revert -eq 1 ]]; then
      sd -s '"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery"' '"serviceUrl": "https://open-vsx.org/vscode/gallery"' "$prod"
      sd -s '"cacheUrl": "https://vscode.blob.core.windows.net/gallery/index",' '' "$prod"
      sd -s '"itemUrl": "https://marketplace.visualstudio.com/items"' '"itemUrl": "https://open-vsx.org/vscode/item"' "$prod"
      printf "Restored VSCodium to Open-VSX\n"
    else
      sd -s '"serviceUrl": "https://open-vsx.org/vscode/gallery"' '"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery"' "$prod"
      sd '("serviceUrl": "[^"]+")' '$1,\n    "cacheUrl": "https://vscode.blob.core.windows.net/gallery/index"' "$prod"
      sd -s '"itemUrl": "https://open-vsx.org/vscode/item"' '"itemUrl": "https://marketplace.visualstudio.com/items"' "$prod"
      printf "VSCodium marketplace patched\n"
    fi
  else
    if [[ $revert -eq 1 ]]; then
      sed -i \
        -e 's/^[[:blank:]]*"serviceUrl":.*/    "serviceUrl": "https:\/\/open-vsx.org\/vscode\/gallery",/' \
        -e '/^[[:blank:]]*"cacheUrl/d' \
        -e 's/^[[:blank:]]*"itemUrl":.*/    "itemUrl": "https:\/\/open-vsx.org\/vscode\/item"/' \
        -e '/^[[:blank:]]*"linkProtectionTrustedDomains/d' \
        -e '/^[[:blank:]]*"documentationUrl/i\  "linkProtectionTrustedDomains": ["https://open-vsx.org"],' \
        "$prod" && printf "Restored VSCodium to Open-VSX\n"
    else
      sed -i \
        -e 's/^[[:blank:]]*"serviceUrl":.*/    "serviceUrl": "https:\/\/marketplace.visualstudio.com\/_apis\/public\/gallery",/' \
        -e '/^[[:blank:]]*"cacheUrl/d' \
        -e '/^[[:blank:]]*"serviceUrl/a\    "cacheUrl": "https:\/\/vscode.blob.core.windows.net\/gallery\/index",' \
        -e 's/^[[:blank:]]*"itemUrl":.*/    "itemUrl": "https:\/\/marketplace.visualstudio.com\/items"/' \
        -e '/^[[:blank:]]*"linkProtectionTrustedDomains/d' \
        "$prod" && printf "VSCodium marketplace patched\n"
    fi
  fi
}

fix_sign(){
  local -r path="/usr/lib/code/out/vs/code/electron-utility/sharedProcess/sharedProcessMain.js"
  local search replace
  [[ ! -f $path ]] && return 0
  if [[ ${1:-0} -eq 1 ]]; then
    search='import("@vscode/vsce-sign")'
    replace='import("node-ovsx-sign")'
  else
    search='import("node-ovsx-sign")'
    replace='import("@vscode/vsce-sign")'
  fi
  grep -qF "$search" "$path" 2>/dev/null && $SED -i "s|${search}|${replace}|g" "$path"
}

features_patch(){
  local -r prod="${1:-/usr/lib/code/product.json}"
  local -r patch="${2:-/usr/share/code-features/patch.json}"
  local -r cache="${3:-/usr/share/code-features/cache.json}"
  local tmp="${prod}.tmp.$$"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ ! -f $prod ]] && printf "WARN: %s not found. Install extra/code.\n" "$prod" >&2 && return 0
  [[ ! -f $patch ]] && printf "Error: %s not found\n" "$patch" >&2 && return 1
  [[ ! -f $cache ]] && printf '{}' >"$cache"

  $JQ -s '
    .[0] as $prod | .[1] as $patch |
    ($prod | to_entries | map(select(.key as $k | $patch | has($k))) | from_entries) as $saved |
    ($prod + $patch) as $merged |
    {product: $merged, cache: $saved}
  ' "$prod" "$patch" >"$tmp" || return 1

  $JQ -r '.product' "$tmp" >"${prod}" || return 1
  $JQ -r '.cache' "$tmp" >"${cache}" || return 1
  rm -f "$tmp" &>/dev/null || :
  printf "Applied code-features patch\n"
}

features_restore(){
  local -r prod="${1:-/usr/lib/code/product.json}"
  local -r patch="${2:-/usr/share/code-features/patch.json}"
  local -r cache="${3:-/usr/share/code-features/cache.json}"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ ! -f $prod || ! -f $patch || ! -f $cache ]] && printf "Error: Required files missing\n" >&2 && return 1

  $JQ -s '
    .[0] as $prod | .[1] as $patch | .[2] as $cache |
    ($prod | to_entries | map(select(.key as $k | ($patch | has($k)) | not)) | from_entries) as $cleaned |
    ($cleaned + $cache)
  ' "$prod" "$patch" "$cache" >"${prod}.tmp.$$" || return 1

  mv -f "${prod}.tmp.$$" "$prod" || return 1
  printf "Restored code-features\n"
}

features_update(){
  local ver="${1:-$($JQ -r .version /usr/lib/code/product.json 2>/dev/null)}"
  local work="/tmp/code-features.$$"
  local url="https://update.code.visualstudio.com/${ver}/linux-x64/stable"
  local patch="${2:-./patch.json}"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ -z $ver ]] && printf "Error: Version required\n" >&2 && return 1

  mkdir -p "$work" || return 1
  printf "Downloading VSCode %s...\n" "$ver"
  dl "$url" "$work/code.tgz" || { rm -rf "$work"; return 1; }
  tar xf "$work/code.tgz" -C "$work" || { rm -rf "$work"; return 1; }

  local -a keys=(nameShort nameLong applicationName serverApplicationName urlProtocol
    dataFolderName serverDataFolderName webUrl webEndpointUrl webEndpointUrlTemplate
    webviewContentExternalBaseUrlTemplate commandPaletteSuggestedCommandIds extensionKeywords
    aiConfig settingsSearchUrl extensionEnabledApiProposals tasConfig extensionKind
    extensionPointExtensionKind extensionSyncedKeys extensionVirtualWorkspacesSupport
    trustedExtensionAuthAccess auth "configurationSync.store" "editSessions.store"
    tunnelApplicationName tunnelApplicationConfig)

  $JQ -r --argjson keys "$(printf '%s\n' "${keys[@]}" | $JQ -R . | $JQ -s .)" \
    'reduce $keys[] as $k ({}; . + {($k): (getpath($k | split("."))?)}) | . + {enableTelemetry: false}' \
    "$work/VSCode-linux-x64/resources/app/product.json" >"$patch" || { rm -rf "$work"; return 1; }

  rm -rf "$work"
  printf "Updated %s\n" "$patch"
  [[ -f ./PKGBUILD ]] && command -v updpkgsums &>/dev/null && updpkgsums ./PKGBUILD
}

marketplace_patch(){
  local -r prod="${1:-/usr/lib/code/product.json}"
  local -r patch="${2:-/usr/share/code-marketplace/patch.json}"
  local -r cache="${3:-/usr/share/code-marketplace/cache.json}"
  local tmp="${prod}.tmp.$$"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ ! -f $prod ]] && printf "WARN: %s not found. Install extra/code.\n" "$prod" >&2 && return 0
  [[ ! -f $patch ]] && printf "Error: %s not found\n" "$patch" >&2 && return 1
  [[ ! -f $cache ]] && printf '{}' >"$cache"

  $JQ -s '
    .[0] as $prod | .[1] as $patch |
    ($prod | to_entries | map(select(.key as $k | $patch | has($k))) | from_entries) as $saved |
    ($prod + $patch) as $merged |
    {product: $merged, cache: $saved}
  ' "$prod" "$patch" >"$tmp" || return 1

  $JQ -r '.product' "$tmp" >"${prod}" || return 1
  $JQ -r '.cache' "$tmp" >"${cache}" || return 1
  rm -f "$tmp" &>/dev/null || :
  fix_sign 0
  printf "Applied code-marketplace patch\n"
}

marketplace_restore(){
  local -r prod="${1:-/usr/lib/code/product.json}"
  local -r patch="${2:-/usr/share/code-marketplace/patch.json}"
  local -r cache="${3:-/usr/share/code-marketplace/cache.json}"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ ! -f $prod || ! -f $patch || ! -f $cache ]] && printf "Error: Required files missing\n" >&2 && return 1

  $JQ -s '
    .[0] as $prod | .[1] as $patch | .[2] as $cache |
    ($prod | to_entries | map(select(.key as $k | ($patch | has($k)) | not)) | from_entries) as $cleaned |
    ($cleaned + $cache)
  ' "$prod" "$patch" "$cache" >"${prod}.tmp.$$" || return 1

  mv -f "${prod}.tmp.$$" "$prod" || return 1
  fix_sign 1
  printf "Restored code-marketplace\n"
}

marketplace_update(){
  local ver="${1}"
  local work="/tmp/code-marketplace.$$"
  local url="https://update.code.visualstudio.com/${ver}/linux-x64/stable"
  local patch="${2:-./patch.json}"

  command -v $JQ &>/dev/null || { printf "Error: jq/jaq required\n" >&2; return 1; }
  [[ -z $ver ]] && printf "Error: Version required\n" >&2 && return 1

  mkdir -p "$work" || return 1
  printf "Downloading VSCode %s...\n" "$ver"
  dl "$url" "$work/code.tgz" || { rm -rf "$work"; return 1; }
  tar xf "$work/code.tgz" -C "$work" || { rm -rf "$work"; return 1; }

  local -a keys=(extensionsGallery extensionRecommendations keymapExtensionTips
    languageExtensionTips configBasedExtensionTips webExtensionTips
    virtualWorkspaceExtensionTips remoteExtensionTips extensionAllowedBadgeProviders
    extensionAllowedBadgeProvidersRegex msftInternalDomains linkProtectionTrustedDomains)

  $JQ -r --argjson keys "$(printf '%s\n' "${keys[@]}" | $JQ -R . | $JQ -s .)" \
    'reduce $keys[] as $k ({}; . + {($k): .[$k]})' \
    "$work/VSCode-linux-x64/resources/app/product.json" >"$patch" || { rm -rf "$work"; return 1; }

  rm -rf "$work"
  printf "Updated %s\n" "$patch"
  [[ -f ./PKGBUILD ]] && command -v updpkgsums &>/dev/null && updpkgsums ./PKGBUILD
}

main(){
  case "${1:-}" in
    xdg|--xdg) xdg_patch ;;
    vscodium|--vscodium) vscodium_marketplace "$2" 0 ;;
    vscodium-restore|--vscodium-restore) vscodium_marketplace "$2" 1 ;;
    feat|--feat) features_patch "$2" "$3" "$4" ;;
    feat-restore|--feat-restore) features_restore "$2" "$3" "$4" ;;
    feat-update|--feat-update) features_update "$2" "$3" ;;
    mkt|--mkt) marketplace_patch "$2" "$3" "$4" ;;
    mkt-restore|--mkt-restore) marketplace_restore "$2" "$3" "$4" ;;
    mkt-update|--mkt-update) marketplace_update "$2" "$3" ;;
    all|--all)
      find_vscode_files | xdg_patch
      vscodium_marketplace "$2" 0
      marketplace_patch
      features_patch
      ;;
    *) cat >&2 <<'EOF'
Usage: vscode-patch.sh <cmd> [args]

XDG Patches:
  xdg                                Apply XDG desktop patches (stdin)

VSCodium:
  vscodium [product.json]            Switch to MS Marketplace
  vscodium-restore [product.json]    Restore to Open-VSX

Code-Features (Official Build Features):
  feat [prod] [patch] [cache]        Apply features patch
  feat-restore [prod] [patch] [cache] Restore original
  feat-update [ver] [patch.json]     Update from upstream

Code-Marketplace (Gallery & Extensions):
  mkt [prod] [patch] [cache]         Apply marketplace patch
  mkt-restore [prod] [patch] [cache] Restore original
  mkt-update <ver> [patch.json]      Update from upstream

Combined:
  all [vscodium-prod]                Apply all patches

Examples:
  find_vscode_files | vscode-patch.sh xdg
  sudo vscode-patch.sh vscodium
  sudo vscode-patch.sh vscodium-restore
  sudo vscode-patch.sh mkt
  sudo vscode-patch.sh feat
  vscode-patch.sh mkt-update 1.95.0
  sudo vscode-patch.sh all

Defaults:
  VSCode:    /usr/lib/code/product.json
  VSCodium:  /usr/share/vscodium/resources/app/product.json
  Features:  /usr/share/code-features/{patch,cache}.json
  Marketplace: /usr/share/code-marketplace/{patch,cache}.json

Tools: Prefers sd>sed, jaq>jq, curl>wget
EOF
      return 1
      ;;
  esac
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && main "$@"
