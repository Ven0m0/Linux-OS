#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C LANG=C
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
    aria2c -q --max-tries=3 --retry-wait=1 -d "${"$out"%/*}" -o "${"$out"##*/}" "$url"
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
    *.desktop)
      fix_214741 "$file"
      fix_15741 "$file"
      printf '%b\n' "${GRN}✓${DEF} $file" ;;
    */package.json)
      fix_129953 "$file"; printf '%b\n' "${GRN}✓${DEF} $file" ;;
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
xdg_datafolder(){
  local prod="${1:-/usr/share/vscodium/resources/app/product.json}"
  [[ ! -f $prod ]] && die "Not found: $prod"
  sed -i 's|"dataFolderName": ".*"|"dataFolderName": ".local/share/codium"|' "$prod"
  printf '%b\n' "${GRN}✓ XDG dataFolderName → .local/share/codium${DEF}"
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
  [[ ${1:-0} -eq 1 ]] && sed -i 's|import("@vscode/vsce-sign")|import("node-ovsx-sign")|g' "$path" \
    || sed -i 's|import("node-ovsx-sign")|import("@vscode/vsce-sign")|g' "$path"
}
#──────────── VSCodium Product Patcher ────
vscodium_prod_patch(){
  local vscodium_prod="${1:-/usr/share/vscodium/resources/app/product.json}"
  local backup="${vscodium_prod}.backup.$$"
  local work="/tmp/vscodium-patch.$$"
  local vscode_prod="$work/product.json"
  [[ ! -f $vscodium_prod ]] && die "VSCodium product.json not found: $vscodium_prod"
  local vscodium_ver
  vscodium_ver=$($JQ -r '.version // empty' "$vscodium_prod" 2>/dev/null)
  [[ -z $vscodium_ver ]] && die "Cannot determine VSCodium version"
  mkdir -p "$work" || die "Failed to create work dir"
  echo "Fetching VSCode $vscodium_ver product.json..."
  local url="https://update.code.visualstudio.com/${vscodium_ver}/linux-x64/stable"
  download_file "$url" "$work/vscode.tgz" || { rm -rf "$work"; die "Download failed"; }
  tar xf "$work/vscode.tgz" -C "$work" --strip-components=3 \
    VSCode-linux-x64/resources/app/product.json 2>/dev/null || { rm -rf "$work"; die "Failed to extract product.json"; }
  [[ ! -f $vscode_prod ]] && { rm -rf "$work"; die "VSCode product.json not found in archive"; }
  cp -f "$vscodium_prod" "$backup" || { rm -rf "$work"; die "Backup failed"; }
  $JQ -s '
    .[0] as $vscodium | .[1] as $vscode |
    $vscodium + {
      nameShort: $vscode.nameShort,
      nameLong: $vscode.nameLong,
      applicationName: $vscode.applicationName,
      dataFolderName: $vscode.dataFolderName,
      serverDataFolderName: $vscode.serverDataFolderName,
      darwinBundleIdentifier: $vscode.darwinBundleIdentifier,
      linuxIconName: $vscode.linuxIconName,
      licenseUrl: $vscode.licenseUrl,
      extensionAllowedProposedApi: $vscode.extensionAllowedProposedApi,
      extensionEnabledApiProposals: $vscode.extensionEnabledApiProposals,
      extensionKind: $vscode.extensionKind,
      extensionPointExtensionKind: $vscode.extensionPointExtensionKind,
      extensionSyncedKeys: $vscode.extensionSyncedKeys,
      extensionVirtualWorkspacesSupport: $vscode.extensionVirtualWorkspacesSupport,
      extensionsGallery: $vscode.extensionsGallery,
      extensionTips: $vscode.extensionTips,
      extensionImportantTips: $vscode.extensionImportantTips,
      exeBasedExtensionTips: $vscode.exeBasedExtensionTips,
      configBasedExtensionTips: $vscode.configBasedExtensionTips,
      keymapExtensionTips: $vscode.keymapExtensionTips,
      languageExtensionTips: $vscode.languageExtensionTips,
      remoteExtensionTips: $vscode.remoteExtensionTips,
      webExtensionTips: $vscode.webExtensionTips,
      virtualWorkspaceExtensionTips: $vscode.virtualWorkspaceExtensionTips,
      trustedExtensionAuthAccess: $vscode.trustedExtensionAuthAccess,
      trustedExtensionUrlPublicKeys: $vscode.trustedExtensionUrlPublicKeys,
      auth: $vscode.auth,
      configurationSync: $vscode.configurationSync,
      "configurationSync.store": $vscode."configurationSync.store",
      editSessions: $vscode.editSessions,
      "editSessions.store": $vscode."editSessions.store",
      settingsSync: $vscode.settingsSync,
      aiConfig: $vscode.aiConfig,
      commandPaletteSuggestedCommandIds: $vscode.commandPaletteSuggestedCommandIds,
      extensionRecommendations: $vscode.extensionRecommendations,
      extensionKeywords: $vscode.extensionKeywords,
      extensionAllowedBadgeProviders: $vscode.extensionAllowedBadgeProviders,
      extensionAllowedBadgeProvidersRegex: $vscode.extensionAllowedBadgeProvidersRegex,
      linkProtectionTrustedDomains: $vscode.linkProtectionTrustedDomains,
      msftInternalDomains: $vscode.msftInternalDomains,
      documentationUrl: $vscode.documentationUrl,
      introductoryVideosUrl: $vscode.introductoryVideosUrl,
      tipsAndTricksUrl: $vscode.tipsAndTricksUrl,
      newsletterSignupUrl: $vscode.newsletterSignupUrl,
      releaseNotesUrl: $vscode.releaseNotesUrl,
      keyboardShortcutsUrlMac: $vscode.keyboardShortcutsUrlMac,
      keyboardShortcutsUrlLinux: $vscode.keyboardShortcutsUrlLinux,
      keyboardShortcutsUrlWin: $vscode.keyboardShortcutsUrlWin,
      quality: $vscode.quality,
      settingsSearchUrl: $vscode.settingsSearchUrl,
      tasConfig: $vscode.tasConfig,
      tunnelApplicationName: $vscode.tunnelApplicationName,
      tunnelApplicationConfig: $vscode.tunnelApplicationConfig,
      serverApplicationName: $vscode.serverApplicationName,
      serverGreeting: $vscode.serverGreeting,
      urlProtocol: $vscode.urlProtocol,
      webUrl: $vscode.webUrl,
      webEndpointUrl: $vscode.webEndpointUrl,
      webEndpointUrlTemplate: $vscode.webEndpointUrlTemplate,
      webviewContentExternalBaseUrlTemplate: $vscode.webviewContentExternalBaseUrlTemplate,
      builtInExtensions: $vscode.builtInExtensions,
      extensionAllowedExtensionKinds: $vscode.extensionAllowedExtensionKinds,
      crash: $vscode.crash,
      enableTelemetry: false,
      aiRelatedInformationUrl: $vscode.aiRelatedInformationUrl,
      defaultChatAgent: $vscode.defaultChatAgent
    }
  ' "$vscodium_prod" "$vscode_prod" >"${vscodium_prod}.tmp" || {
    mv -f "$backup" "$vscodium_prod"; rm -rf "$work"
    die "JQ merge failed"
  }
  mv -f "${vscodium_prod}.tmp" "$vscodium_prod" || {
    mv -f "$backup" "$vscodium_prod"; rm -rf "$work"
    die "Failed to write patched product.json"
  }
  sed -i 's|"dataFolderName": ".*"|"dataFolderName": ".local/share/codium"|' "$vscodium_prod"
  rm -rf "$work"
  printf '%b\n' "${GRN}✓ VSCodium product.json patched (backup: $backup)${DEF}"
  echo "  Merged all MS features, telemetry disabled, XDG-compliant"
}
vscodium_prod_restore(){
  local vscodium_prod="${1:-/usr/share/vscodium/resources/app/product.json}" backup
  backup=$(ls -t "${vscodium_prod}.backup."* 2>/dev/null | head -1)
  [[ -z $backup ]] && die "No backup found for $vscodium_prod"
  cp -f "$backup" "$vscodium_prod" || die "Restore failed"
  printf '%b\n' "${GRN}✓ Restored from $backup${DEF}"
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
  local prod="${1:-/usr/lib/code/product.json}" patch="${2:-/usr/share/code-features/patch.json}" cache="${3:-/usr/share/code-features/cache.json}"
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
    "$work/VSCode-linux-x64/resources/app/product.json" >"$patch" || {
    rm -rf "$work"; return 1
  }
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
  xdg | --xdg) xdg_patch ;;
  xdg-data | --xdg-data) xdg_datafolder "${2:-}" ;;
  vscodium | --vscodium) vscodium_marketplace "${2:-}" 0 ;;
  vscodium-restore | --vscodium-restore) vscodium_marketplace "${2:-}" 1 ;;
  vscodium-prod | --vscodium-prod) vscodium_prod_patch "${2:-}" ;;
  vscodium-prod-restore | --vscodium-prod-restore) vscodium_prod_restore "${2:-}" ;;
  feat | --feat) features_patch "${2:-}" "${3:-}" "${4:-}" ;;
  feat-restore | --feat-restore) features_restore "${2:-}" "${3:-}" "${4:-}" ;;
  feat-update | --feat-update) features_update "${2:-}" "${3:-}" ;;
  mkt | --mkt) marketplace_patch "${2:-}" "${3:-}" "${4:-}" ;;
  mkt-restore | --mkt-restore) marketplace_restore "${2:-}" "${3:-}" "${4:-}" ;;
  mkt-update | --mkt-update) marketplace_update "${2:-}" "${3:-}" ;;
  all | --all)
    find_vscode_files | xdg_patch
    vscodium_marketplace "${2:-}" 0
    marketplace_patch
    features_patch ;;
  all-vscodium | --all-vscodium)
    find_vscode_files | xdg_patch
    vscodium_prod_patch "${2:-}" ;;
  *)
    cat >&2 <<'EOF'
Usage: vscodium-patch.sh <cmd> [args]

XDG:
  xdg                              Apply desktop patches (stdin)
  xdg-data [prod]                  Force XDG-compliant dataFolderName

VSCodium (Simple):
  vscodium [prod]                  → MS Marketplace
  vscodium-restore [prod]          ← Open-VSX

VSCodium (Comprehensive):
  vscodium-prod [prod]             Merge ALL MS features + XDG data dir
  vscodium-prod-restore [prod]     Restore from backup

Features (VSCode):
  feat [prod] [patch] [cache]      Apply patch
  feat-restore [prod] [patch]      Restore
  feat-update [ver] [patch.json]   Update from upstream

Marketplace (VSCode):
  mkt [prod] [patch] [cache]       Apply patch
  mkt-restore [prod] [patch]       Restore
  mkt-update <ver> [patch.json]    Update from upstream

Combined:
  all [vscodium-prod]              Apply all patches (simple)
  all-vscodium [prod]              Apply all + comprehensive VSCodium

Examples:
  # XDG fixes
  find_vscode_files | sudo vscodium-patch.sh xdg
  
  # XDG dataFolderName override
  sudo vscodium-patch.sh xdg-data
  
  # Comprehensive VSCodium (recommended)
  sudo vscodium-patch.sh vscodium-prod
  
  # VSCode patches
  sudo vscodium-patch.sh mkt && sudo vscodium-patch.sh feat
  
  # All-in-one VSCodium
  sudo vscodium-patch.sh all-vscodium

Defaults:
  VSCode:      /usr/lib/code/product.json
  VSCodium:    /usr/share/vscodium/resources/app/product.json
  Features:    /usr/share/code-features/{patch,cache}.json
  Marketplace: /usr/share/code-marketplace/{patch,cache}.json
EOF
    return 1;;
  esac
}
main "$@"
