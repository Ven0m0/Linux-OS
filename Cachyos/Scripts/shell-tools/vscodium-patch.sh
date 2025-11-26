#!/usr/bin/env bash
set -uo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'; LC_ALL=C
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' D=$'\e[0m'
warn(){ printf '%b\n' "${Y}WARN:${D} $*" >&2; }
die(){ printf '%b\n' "${R}ERR:${D} $*" >&2; exit "${2:-1}"; }
has(){ command -v "$1" &>/dev/null; }
has jaq && JQ=jaq || JQ=jq; has "$JQ" || die "Need jq/jaq"

# Keys to migrate from VSCode -> VSCodium
KEYS_PROD=(nameShort nameLong applicationName dataFolderName serverDataFolderName darwinBundleIdentifier linuxIconName licenseUrl extensionAllowedProposedApi extensionEnabledApiProposals extensionKind extensionPointExtensionKind extensionSyncedKeys extensionVirtualWorkspacesSupport extensionsGallery extensionTips extensionImportantTips exeBasedExtensionTips configBasedExtensionTips keymapExtensionTips languageExtensionTips remoteExtensionTips webExtensionTips virtualWorkspaceExtensionTips trustedExtensionAuthAccess trustedExtensionUrlPublicKeys auth configurationSync "configurationSync.store" editSessions "editSessions.store" settingsSync aiConfig commandPaletteSuggestedCommandIds extensionRecommendations extensionKeywords extensionAllowedBadgeProviders extensionAllowedBadgeProvidersRegex linkProtectionTrustedDomains msftInternalDomains documentationUrl introductoryVideosUrl tipsAndTricksUrl newsletterSignupUrl releaseNotesUrl keyboardShortcutsUrlMac keyboardShortcutsUrlLinux keyboardShortcutsUrlWin quality settingsSearchUrl tasConfig tunnelApplicationName tunnelApplicationConfig serverApplicationName serverGreeting urlProtocol webUrl webEndpointUrl webEndpointUrlTemplate webviewContentExternalBaseUrlTemplate builtInExtensions extensionAllowedExtensionKinds crash aiRelatedInformationUrl defaultChatAgent)

dl(){
  local u="$1" o="$2"; mkdir -p "${o%/*}"
  if has aria2c; then aria2c -q --max-tries=3 --retry-wait=1 -d "${o%/*}" -o "${o##*/}" "$u"
  elif has curl; then curl -fsSL --retry 3 --http2 --tlsv1.2 "$u" -o "$o"
  elif has wget; then wget -qO "$o" "$u"
  else die "Need aria2c/curl/wget"; fi
}
# ─── XDG & Files ───
xdg_patch(){
  while read -r f; do
    case "$f" in
      *.desktop)
        grep -q "text/plain" "$f" || sed -i -E 's#^(MimeType=.*);$#\1;text/plain;#' "$f"
        grep -q "inode/directory" "$f" || sed -i -E 's#^(MimeType=.*);$#\1;inode/directory;#' "$f" ;;
      */package.json) sed -i -E 's/"desktopName":[[:space:]]*"(.+)-url-handler\.desktop"/"desktopName": "\1.desktop"/' "$f" ;;
      *) echo "none found" ;;
    esac; printf '%b\n' "${G}✓${D} $f"
  done
}
find_files(){
  printf '%s\n' /usr/lib/code*/package.json /opt/visual-studio-code*/resources/app/package.json \
    /opt/vscodium*/resources/app/package.json /usr/share/applications/{code,vscode,vscodium}*.desktop \
    | grep -vE '\-url-handler.desktop$'
}
# ─── JSON Logic ───
# $1=prod $2=patch $3=cache
apply_json(){
  [[ ! -f $1 ]] && { warn "$1 missing"; return 0; }
  [[ ! -f $2 ]] && die "Patch missing: $2"
  [[ ! -f $3 ]] && echo '{}' >"$3"
  local t="$1.tmp.$$"
  "$JQ" -s '.[0] as $b|.[1] as $p|($b|to_entries|map(select(.key as $k|$p|has($k)))|from_entries) as $c|($b+$p)|{p:.,c:$c}' "$1" "$2" >"$t" || return 1
  "$JQ" -r .p "$t" >"$1" && "$JQ" -r .c "$t" >"$3" && rm "$t" && printf '%b\n' "${G}Applied to $1${D}"
}
# $1=prod $2=patch $3=cache
restore_json(){
  [[ ! -f $1 || ! -f $3 ]] && die "Files missing for $1"
  local t="$1.tmp.$$"
  "$JQ" -s '.[0] as $b|.[1] as $p|.[2] as $c|($b|to_entries|map(select(.key as $k|($p|has($k))|not))|from_entries)+$c' "$1" "$2" "$3" >"$t" || return 1
  mv "$t" "$1" && printf '%b\n' "${G}Restored $1${D}"
}
# $1=ver $2=out_patch $3=keys_array_name
update_json(){
  local v="$1" out="$2" work="/tmp/code-up.$$" u="https://update.code.visualstudio.com/${1}/linux-x64/stable"
  [[ -z $v ]] && die "Version required"
  local -n kref="$3"; echo "⬇ VSCode $v..."
  dl "$u" "$work/c.tgz" || { rm -rf "$work"; return 1; }
  tar xf "$work/c.tgz" -C "$work" --strip-components=3 VSCode-linux-x64/resources/app/product.json
  "$JQ" -r --argjson k "$(printf '%s\n' "${kref[@]}" | "$JQ" -R . | "$JQ" -s .)" \
    'reduce $k[] as $x ({}; . + {($x): (getpath($x|split("."))?)}) | . + {enableTelemetry:false}' \
    "$work/product.json" >"$out"
  rm -rf "$work"; printf '%b\n' "${G}Updated $out${D}"
  [[ -f ./PKGBUILD ]] && has updpkgsums && updpkgsums ./PKGBUILD || :
}

# ─── Specifics ───
sign_fix(){
  local f="/usr/lib/code/out/vs/code/electron-utility/sharedProcess/sharedProcessMain.js"
  [[ -f $f ]] && sed -i "s|import(\"${1:-@vscode/vsce-sign}\")|import(\"${2:-node-ovsx-sign}\")|g" "$f"
}
repo_swap(){
  local f="${1:-/usr/share/vscodium/resources/app/product.json}"
  [[ ! -f $f ]] && die "No product.json"
  if [[ ${2:-0} -eq 1 ]]; then
    sed -i -e 's|"serviceUrl":.*|"serviceUrl": "https://open-vsx.org/vscode/gallery",|' \
           -e '/"cacheUrl/d' -e 's|"itemUrl":.*|"itemUrl": "https://open-vsx.org/vscode/item"|' \
           -e '/"linkProtectionTrustedDomains/d' -e '/"documentationUrl/i\  "linkProtectionTrustedDomains": ["https://open-vsx.org"],' "$f"
    printf '%b\n' "${G}Repo: Open-VSX${D}"
  else
    sed -i -e 's|"serviceUrl":.*|"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",|' \
           -e '/"cacheUrl/d' -e '/"serviceUrl/a\    "cacheUrl": "https://vscode.blob.core.windows.net/gallery/index",' \
           -e 's|"itemUrl":.*|"itemUrl": "https://marketplace.visualstudio.com/items"|' \
           -e '/"linkProtectionTrustedDomains/d' "$f"
    printf '%b\n' "${G}Repo: MS Marketplace${D}"
  fi
}
vscodium_prod_full(){
  local dst="${1:-/usr/share/vscodium/resources/app/product.json}"
  local work="/tmp/vp.$$" v; local src="${work}/product.json"
  [[ ! -f $dst ]] && die "Missing $dst"
  v=$("$JQ" -r '.version//empty' "$dst") || die "No version"
  cp "$dst" "${dst}.backup.$$(date +%s)"; dl "https://update.code.visualstudio.com/$v/linux-x64/stable" "${work}/c.tgz"
  tar xf "${work}/c.tgz" -C "$work" --strip-components=3 VSCode-linux-x64/resources/app/product.json
  "$JQ" -s --argjson k "$(printf '%s\n' "${KEYS_PROD[@]}" | "$JQ" -R . | "$JQ" -s .)" \
    '.[0] as $d | .[1] as $s | $d + ($s | with_entries(select(.key as $x | $k | index($x)))) | . + {enableTelemetry:false}' \
    "$dst" "$src" > "${dst}.tmp" && mv "${dst}.tmp" "$dst"
  sed -i 's|"dataFolderName": ".*"|"dataFolderName": ".local/share/codium"|' "$dst"
  rm -rf "$work"; printf '%b\n' "${G}✓ Patched VSCodium Full${D}"
}
vscodium_restore(){
  local d="${1:-/usr/share/vscodium/resources/app/product.json}"
  local b; b=$(find "${d%/*}" -maxdepth 1 -name "${d##*/}.backup.*" -printf "%T@ %p\n" | sort -rn | head -1 | cut -d' ' -f2-)
  [[ -z $b ]] && die "No backup"
  cp -f "$b" "$d" && printf '%b\n' "${G}✓ Restored $b${D}"
}
# ─── Main ───
main(){
  local C_P="/usr/lib/code/product.json" C_DIR="/usr/share"
  case "${1:-}" in
    xdg) xdg_patch ;;
    xdg-data) f="${2:-/usr/share/vscodium/resources/app/product.json}"; sed -i 's|"dataFolderName": ".*"|"dataFolderName": ".local/share/codium"|' "$f" && echo "✓ DataFolder" ;;
    vscodium) repo_swap "${2:-}" 0 ;;
    vscodium-restore) repo_swap "${2:-}" 1 ;;
    vscodium-prod) vscodium_prod_full "${2:-}" ;;
    vscodium-prod-restore) vscodium_restore "${2:-}" ;;
    feat) apply_json "${2:-$C_P}" "${3:-$C_DIR/code-features/patch.json}" "${4:-$C_DIR/code-features/cache.json}" ;;
    feat-restore) restore_json "${2:-$C_P}" "${3:-$C_DIR/code-features/patch.json}" "${4:-$C_DIR/code-features/cache.json}" ;;
    feat-update) update_json "${2:-}" "${3:-./patch.json}" KEYS_PROD ;; # Using PROD keys as superset
    mkt) apply_json "${2:-$C_P}" "${3:-$C_DIR/code-marketplace/patch.json}" "${4:-$C_DIR/code-marketplace/cache.json}"; sign_fix node-ovsx-sign ;;
    mkt-restore) restore_json "${2:-$C_P}" "${3:-$C_DIR/code-marketplace/patch.json}" "${4:-$C_DIR/code-marketplace/cache.json}"; sign_fix ;;
    mkt-update) K=(extensionsGallery extensionRecommendations keymapExtensionTips languageExtensionTips configBasedExtensionTips webExtensionTips virtualWorkspaceExtensionTips remoteExtensionTips extensionAllowedBadgeProviders extensionAllowedBadgeProvidersRegex msftInternalDomains linkProtectionTrustedDomains); update_json "${2:-}" "${3:-./patch.json}" K ;;
    all) find_files | xdg_patch; repo_swap "" 0; apply_json "$C_P" "$C_DIR/code-marketplace/patch.json" "$C_DIR/code-marketplace/cache.json"; apply_json "$C_P" "$C_DIR/code-features/patch.json" "$C_DIR/code-features/cache.json"; sign_fix node-ovsx-sign ;;
    all-vscodium) find_files | xdg_patch; vscodium_prod_full "${2:-}" ;;
    *) printf "Usage: %s {xdg|xdg-data|vscodium[-prod][-restore]|feat[-restore|-update]|mkt[-restore|-update]|all[-vscodium]}\n" "$0"; exit 1 ;;
  esac
}
main "$@"
