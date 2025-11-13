#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C LANG=C

#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

#──────────── Core Helpers ────────────────
has(){ command -v "$1" &>/dev/null; }
die(){ printf '%b\n' "${RED}Error:${DEF} $*" >&2; exit "${2:-1}"; }

JQ=$(has jaq && echo jaq || has jq && echo jq || die "jq/jaq required")

download_file(){
  local url=$1 out=$2
  if has aria2c; then
    aria2c -q --max-tries=3 --retry-wait=1 -d "$(dirname "$out")" -o "$(basename "$out")" "$url"
  elif has curl; then
    curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$out"
  elif has wget; then
    wget -qO "$out" "$url"
  else
    die "aria2c, curl, or wget required"
  fi
}

#──────────── XDG Patches ─────────────────
add_mime_type(){ grep -qE "^MimeType=.*\b${1};" "$2" || sed -i -E "s#^(MimeType=.*;)\$#\1${1};#" "$2"; }
fix_15741(){ add_mime_type 'inode/directory' "$1"; }
fix_129953(){ sed -i -E 's/"desktopName":[[:space:]]*"(.+)-url-handler\.desktop"/"desktopName": "\1.desktop"/' "$1"; }
fix_214741(){ add_mime_type 'text/plain' "$1"; }
xdg_patch(){
  while read -r file; do
    case "$file" in
      *.desktop) fix_214741 "$file"; fix_15741 "$file"; printf '%b\n' "${GRN}✓${DEF} $file" ;;
      */package.json) fix_129953 "$file"; printf '%b\n' "${GRN}✓${DEF} $file" ;;
      *) printf '%b\n' "${YLW}?${DEF} $file" ;;
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

#──────────── VSCodium Marketplace ────────
vscodium_marketplace(){
  local prod="${1:-/usr/share/vscodium/resources/app/product.json}" revert="${2:-0}"
  [[ ! -f $prod ]] && die "Not found: $prod" 1
  if [[ $revert -eq 1 ]]; then
    sed -i \
      -e 's/^[[:blank:]]*"serviceUrl":.*/    "serviceUrl": "https:\/\/open-vsx.org\/vscode\/gallery",/' \
      -e '/^[[:blank:]]*"cacheUrl/d' \
      -e 's/^[[:blank:]]*"itemUrl":.*/    "itemUrl": "https:\/\/open-vsx.org\/vscode\/item"/' \
      -e '/^[[:blank:]]*"linkProtectionTrustedDomains/d' \
      -e '/^[[:blank:]]*"documentationUrl/i\  "linkProtectionTrustedDomains": ["https://open-vsx.org"],' \
      "$prod"
    printf '%b\n' "${GRN}Restored VSCodium → Open-VSX${DEF}"
  else
    sed -i \
      -e 's/^[[:blank:]]*"serviceUrl":.*/    "serviceUrl": "https:\/\/marketplace.visualstudio.com\/_apis\/public\/gallery",/' \
      -e '/^[[:blank:]]*"cacheUrl/d' \
      -e '/^[[:blank:]]*"serviceUrl/a\    "cacheUrl": "https:\/\/vscode.blob.core.windows.net\/gallery\/index",' \
      -e 's/^[[:blank:]]*"itemUrl":.*/    "itemUrl": "https:\/\/marketplace.visualstudio.com\/items"/' \
      -e '/^[[:blank:]]*"linkProtectionTrustedDomains/d' \
      "$prod"
    printf '%b\n' "${GRN}VSCodium → MS Marketplace${DEF}"
  fi
}

#──────────── Sign Fix ────────────────────
fix_sign(){
  local path="/usr/lib/code/out/vs/code/electron-utility/sharedProcess/sharedProcessMain.js"
  [[ ! -f $path ]] && return 0
  if [[ ${1:-0} -eq 1 ]]; then
    sed -i 's|import("@vscode/vsce-sign")|import("node-ovsx-sign")|g' "$path"
  else
    sed -i 's|import("node-ovsx-sign")|import("@vscode/vsce-sign")|g' "$path"
  fi
}

#──────────── Code-Features ───────────────
features_patch(){
  local prod="${1:-/usr/lib/code/product.json}" patch="${2:-/usr/share/code-features/patch.json}" cache="${3:-/usr/share/code-features/cache.json}"
  local tmp="${prod}.tmp.$$"
  [[ ! -f $prod ]] && printf '%b\n' "${YLW}WARN: $prod missing (install extra/code)${DEF}" && return 0
  [[ ! -f $patch ]] && die "Patch missing: $patch"
  [[ ! -f $cache ]] && printf '{}' >"$cache"
  $JQ -s '
    .[0] as $prod | .[1] as $patch |
    ($prod | to_entries | map(select(.key as $k | $patch | has($k))) | from_entries) as $saved |
    ($prod + $patch) as $merged |
    {product: $merged, cache: $saved}
  ' "$prod" "$patch" >"$tmp" || return 1
  $JQ -r '.product' "$tmp" >"$prod" && $JQ -r '.cache' "$tmp" >"$cache" || return 1
  rm -f "$tmp" &>/dev/null || :
  printf '%b\n' "${GRN}Applied code-features${DEF}"
}

features_restore(){
  local prod="${1:-/usr/lib/code/product.json}"
  local patch="${2:-/usr/share/code-features/patch.json}"
  local cache="${3:-/usr/share/code-features/cache.json}"
  [[ ! -f $prod || ! -f $patch || ! -f $cache ]] && die "Files missing"
  $JQ -s '
    .[0] as $prod | .[1] as $patch | .[2] as $cache |
    ($prod | to_entries | map(select(.key as $k | ($patch | has($k)) | not)) | from_entries) as $cleaned |
    ($cleaned + $cache)
  ' "$prod" "$patch" "$cache" >"${prod}.tmp.$$" || return 1
  mv -f "${prod}.tmp.$$" "$prod" || return 1
  printf '%b\n' "${GRN}Restored code-features${DEF}"
}

features_update(){
  local ver="${1:-$($JQ -r .version /usr/lib/code/product.json 2>/dev/null)}" patch="${2:-./patch.json}"
  local work="/tmp/code-features.$$" url="https://update.code.visualstudio.com/${ver}/linux-x64/stable"
  [[ -z $ver ]] && die "Version required"
  mkdir -p "$work" || return 1
  echo "⬇ VSCode $ver..."
  download_file "$url" "$work/code.tgz" || { rm -rf "$work"; return 1; }
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
  printf '%b\n' "${GRN}Updated $patch${DEF}"
  [[ -f ./PKGBUILD ]] && has updpkgsums && updpkgsums ./PKGBUILD
}

#──────────── Code-Marketplace ────────────
marketplace_patch(){
  local prod="${1:-/usr/lib/code/product.json}" patch="${2:-/usr/share/code-marketplace/patch.json}" cache="${3:-/usr/share/code-marketplace/cache.json}"
  local tmp="${prod}.tmp.$$"
  [[ ! -f $prod ]] && printf '%b\n' "${YLW}WARN: $prod missing (install extra/code)${DEF}" && return 0
  [[ ! -f $patch ]] && die "Patch missing: $patch"
  [[ ! -f $cache ]] && printf '{}' >"$cache"
  $JQ -s '
    .[0] as $prod | .[1] as $patch |
    ($prod | to_entries | map(select(.key as $k | $patch | has($k))) | from_entries) as $saved |
    ($prod + $patch) as $merged |
    {product: $merged, cache: $saved}
  ' "$prod" "$patch" >"$tmp" || return 1
  
  $JQ -r '.product' "$tmp" >"$prod" && $JQ -r '.cache' "$tmp" >"$cache" || return 1
  rm -f "$tmp" &>/dev/null || :
  fix_sign 0
  printf '%b\n' "${GRN}Applied code-marketplace${DEF}"
}

marketplace_restore(){
  local prod="${1:-/usr/lib/code/product.json}" patch="${2:-/usr/share/code-marketplace/patch.json}" cache="${3:-/usr/share/code-marketplace/cache.json}"
  [[ ! -f $prod || ! -f $patch || ! -f $cache ]] && die "Files missing"
  $JQ -s '
    .[0] as $prod | .[1] as $patch | .[2] as $cache |
    ($prod | to_entries | map(select(.key as $k | ($patch | has($k)) | not)) | from_entries) as $cleaned |
    ($cleaned + $cache)
  ' "$prod" "$patch" "$cache" >"${prod}.tmp.$$" || return 1
  mv -f "${prod}.tmp.$$" "$prod" || return 1
  fix_sign 1
  printf '%b\n' "${GRN}Restored code-marketplace${DEF}"
}

marketplace_update(){
  local ver="${1}" patch="${2:-./patch.json}"
  local work="/tmp/code-marketplace.$$" url="https://update.code.visualstudio.com/${ver}/linux-x64/stable"
  [[ -z $ver ]] && die "Version required"
  mkdir -p "$work" || return 1
  echo "⬇ VSCode $ver..."
  download_file "$url" "$work/code.tgz" || { rm -rf "$work"; return 1; }
  tar xf "$work/code.tgz" -C "$work" || { rm -rf "$work"; return 1; }
  local -a keys=(extensionsGallery extensionRecommendations keymapExtensionTips
    languageExtensionTips configBasedExtensionTips webExtensionTips
    virtualWorkspaceExtensionTips remoteExtensionTips extensionAllowedBadgeProviders
    extensionAllowedBadgeProvidersRegex msftInternalDomains linkProtectionTrustedDomains)
  $JQ -r --argjson keys "$(printf '%s\n' "${keys[@]}" | $JQ -R . | $JQ -s .)" \
    'reduce $keys[] as $k ({}; . + {($k): .[$k]})' \
    "$work/VSCode-linux-x64/resources/app/product.json" >"$patch" || { rm -rf "$work"; return 1; }
  rm -rf "$work"
  printf '%b\n' "${GRN}Updated $patch${DEF}"
  [[ -f ./PKGBUILD ]] && has updpkgsums && updpkgsums ./PKGBUILD
}

#──────────── Main ────────────────────────
main(){
  case "${1:-}" in
    xdg|--xdg) xdg_patch ;;
    vscodium|--vscodium) vscodium_marketplace "${2:-}" 0 ;;
    vscodium-restore|--vscodium-restore) vscodium_marketplace "${2:-}" 1 ;;
    feat|--feat) features_patch "${2:-}" "${3:-}" "${4:-}" ;;
    feat-restore|--feat-restore) features_restore "${2:-}" "${3:-}" "${4:-}" ;;
    feat-update|--feat-update) features_update "${2:-}" "${3:-}" ;;
    mkt|--mkt) marketplace_patch "${2:-}" "${3:-}" "${4:-}" ;;
    mkt-restore|--mkt-restore) marketplace_restore "${2:-}" "${3:-}" "${4:-}" ;;
    mkt-update|--mkt-update) marketplace_update "${2:-}" "${3:-}" ;;
    all|--all)
      find_vscode_files | xdg_patch
      vscodium_marketplace "${2:-}" 0
      marketplace_patch
      features_patch
      ;;
    *) cat >&2 <<'EOF'
Usage: vscodium-patch.sh <cmd> [args]

XDG:
  xdg                     Apply desktop patches (stdin)

VSCodium:
  vscodium [prod]         → MS Marketplace
  vscodium-restore [prod] ← Open-VSX

Features:
  feat [prod] [patch] [cache]         Apply patch
  feat-restore [prod] [patch] [cache] Restore
  feat-update [ver] [patch.json]      Update from upstream

Marketplace:
  mkt [prod] [patch] [cache]          Apply patch
  mkt-restore [prod] [patch] [cache]  Restore
  mkt-update <ver> [patch.json]       Update from upstream

All:
  all [vscodium-prod]     Apply all patches

Examples:
  find_vscode_files | sudo vscodium-patch.sh xdg
  sudo vscodium-patch.sh vscodium
  sudo vscodium-patch.sh mkt && sudo vscodium-patch.sh feat
  vscodium-patch.sh mkt-update 1.95.0

Defaults:
  VSCode:      /usr/lib/code/product.json
  VSCodium:    /usr/share/vscodium/resources/app/product.json
  Features:    /usr/share/code-features/{patch,cache}.json
  Marketplace: /usr/share/code-marketplace/{patch,cache}.json
EOF
      return 1
      ;;
  esac
}
main "$@"
