#!/usr/bin/env bash
# VSCode/VSCodium patcher - XDG, marketplace, feature, and privacy patches
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
LC_ALL=C
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' D=$'\e[0m'
warn(){ printf '%b\n' "${Y}⚠${D} $*" >&2; }
die(){
  printf '%b\n' "${R}✗${D} $*" >&2
  exit "${2:-1}"
}
has(){ command -v -- "$1" &>/dev/null; }
ok(){ printf '%b\n' "${G}✓${D} $*"; }

vscode_json_set(){
  local prop=$1 val=$2
  has python3 || {
    warn "No python3: $prop"
    return 1
  }
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name='$prop'
target=json.loads('$val')
home_dir=f'/home/{os.getenv("SUDO_USER",os.getenv("USER"))}'
settings_files=[
  f'{home_dir}/.config/Code/User/settings.json',
  f'{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json',
  f'{home_dir}/.config/VSCodium/User/settings.json',
  f'{home_dir}/.var/app/com.vscodium.codium/config/VSCodium/User/settings.json'
]
changed=0
for sf in settings_files:
  file=Path(sf)
  if not file.exists():
    file.parent.mkdir(parents=True,exist_ok=True)
    file.write_text('{}')
  content=file.read_text()
  if not content.strip(): content='{}'
  try: obj=json.loads(content)
  except json.JSONDecodeError:
    print(f'Invalid JSON in {sf}',file=sys.stderr)
    continue
  if property_name in obj and obj[property_name]==target: continue
  obj[property_name]=target
  file.write_text(json.dumps(obj,indent=2))
  changed+=1
sys.exit(0 if changed>0 else 1)
EOF
}

JQ=
has jaq && JQ=jaq || JQ=jq
has "$JQ" || die "Need jq/jaq"

KEYS_PROD=(nameShort nameLong applicationName dataFolderName serverDataFolderName darwinBundleIdentifier linuxIconName licenseUrl extensionAllowedProposedApi extensionEnabledApiProposals extensionKind extensionPointExtensionKind extensionSyncedKeys extensionVirtualWorkspacesSupport extensionsGallery extensionTips extensionImportantTips exeBasedExtensionTips configBasedExtensionTips keymapExtensionTips languageExtensionTips remoteExtensionTips webExtensionTips virtualWorkspaceExtensionTips trustedExtensionAuthAccess trustedExtensionUrlPublicKeys auth configurationSync "configurationSync.store" editSessions "editSessions.store" settingsSync aiConfig commandPaletteSuggestedCommandIds extensionRecommendations extensionKeywords extensionAllowedBadgeProviders extensionAllowedBadgeProvidersRegex linkProtectionTrustedDomains msftInternalDomains documentationUrl introductoryVideosUrl tipsAndTricksUrl newsletterSignupUrl releaseNotesUrl keyboardShortcutsUrlMac keyboardShortcutsUrlLinux keyboardShortcutsUrlWin quality settingsSearchUrl tasConfig tunnelApplicationName tunnelApplicationConfig serverApplicationName serverGreeting urlProtocol webUrl webEndpointUrl webEndpointUrlTemplate webviewContentExternalBaseUrlTemplate builtInExtensions extensionAllowedExtensionKinds crash aiRelatedInformationUrl defaultChatAgent)

dl(){
  local u=$1 o=$2
  mkdir -p "${o%/*}"
  if has aria2c; then
    aria2c -q --max-tries=3 --retry-wait=1 -d "${o%/*}" -o "${o##*/}" "$u"
  elif has curl; then
    curl -fsSL --retry 3 --http2 --tlsv1.2 "$u" -o "$o"
  elif has wget; then
    wget -qO "$o" "$u"
  else die "Need aria2c/curl/wget"; fi
}

xdg_patch(){
  local -a files=()
  mapfile -t files < <(find /usr/{lib/code*,share/applications} /opt/{visual-studio-code*,vscodium*} \
    -type f \( -name "package.json" -o -name "*.desktop" \) ! -name "*-url-handler.desktop" 2>/dev/null || :)
  ((${#files[@]})) || {
    warn "No XDG files found"
    return 0
  }
  local f mime_added=0
  for f in "${files[@]}"; do
    case $f in
    *.desktop)
      mime_added=0
      grep -qF "text/plain" "$f" || {
        sed -i 's/^\(MimeType=.*\);$/\1;text\/plain;/' "$f"
        ((++mime_added))
      }
      grep -qF "inode/directory" "$f" || {
        sed -i 's/^\(MimeType=.*\);$/\1;inode\/directory;/' "$f"
        ((++mime_added))
      }
      if ((mime_added)); then ok "$f (+${mime_added} MIME)"; else ok "$f (current)"; fi
      ;;
    */package.json)
      sed -i 's/"desktopName":[[:space:]]*"\([^"]*\)-url-handler\.desktop"/"desktopName": "\1.desktop"/' "$f" && ok "$f"
      ;;
    esac
  done
}

json_op(){
  local op=$1 prod=$2 patch=$3 cache=$4
  local tmp="${prod}.tmp.$$"
  [[ -f $prod ]] || {
    warn "$prod missing"
    return 1
  }
  [[ -f $patch ]] || die "Patch missing: $patch"
  case $op in
  apply)
    [[ -f $cache ]] || printf '{}' >"$cache"
    "$JQ" -s '.[0] as $b|.[1] as $p|($b|to_entries|map(select(.key as $k|$p|has($k)))|from_entries) as $c|($b+$p)|{p:.,c:$c}' \
      "$prod" "$patch" >"$tmp" || return 1
    "$JQ" -r .p "$tmp" >"$prod" && "$JQ" -r .c "$tmp" >"$cache" && rm -f "$tmp" && ok "Applied → $prod"
    ;;
  restore)
    [[ -f $cache ]] || die "Cache missing: $cache"
    "$JQ" -s '.[0] as $b|.[1] as $p|.[2] as $c|($b|to_entries|map(select(.key as $k|($p|has($k))|not))|from_entries)+$c' \
      "$prod" "$patch" "$cache" >"$tmp" || return 1
    mv "$tmp" "$prod" && ok "Restored → $prod"
    ;;
  esac
}

update_json(){
  local v=$1 out=$2
  local -n kref="$3"
  [[ $v ]] || die "Version required"
  local work="/tmp/code-up.$$" u="https://update.code.visualstudio.com/${v}/linux-x64/stable"
  printf "⬇ VSCode %s...\n" "$v"
  dl "$u" "$work/c.tgz" || {
    rm -rf "$work"
    return 1
  }
  tar xf "$work/c.tgz" -C "$work" --strip-components=3 VSCode-linux-x64/resources/app/product.json 2>/dev/null
  "$JQ" -r --argjson k "$(printf '%s\n' "${kref[@]}" | "$JQ" -R . | "$JQ" -s .)" \
    'reduce $k[] as $x ({}; . + {($x): (getpath($x|split("."))?)}) | . + {enableTelemetry:false}' \
    "$work/product.json" >"$out"
  rm -rf "$work"
  ok "Updated → $out"
  # shellcheck disable=SC2015 # intentional: updpkgsums failure is non-fatal
  [[ -f ./PKGBUILD ]] && has updpkgsums && updpkgsums ./PKGBUILD &>/dev/null || :
}

sign_fix(){
  local f="/usr/lib/code/out/vs/code/electron-utility/sharedProcess/sharedProcessMain.js"
  local old=${1:-@vscode/vsce-sign} new=${2:-node-ovsx-sign}
  [[ -f $f ]] && sed -i "s|import(\"${old}\")|import(\"${new}\")|g" "$f" && ok "Sign fix: $new"
}

repo_swap(){
  local f=${1:-/usr/share/vscodium/resources/app/product.json} mode=${2:-0}
  [[ -f $f ]] || die "No product.json: $f"
  if ((mode)); then
    sed -i -e 's|"serviceUrl":.*|"serviceUrl": "https://open-vsx.org/vscode/gallery",|' \
      -e '/"cacheUrl"/d' -e 's|"itemUrl":.*|"itemUrl": "https://open-vsx.org/vscode/item"|' \
      -e '/"linkProtectionTrustedDomains"/d' \
      -e '/"documentationUrl"/i\  "linkProtectionTrustedDomains": ["https://open-vsx.org"],' "$f"
    ok "Repo → Open-VSX"
  else
    sed -i -e 's|"serviceUrl":.*|"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",|' \
      -e '/"cacheUrl"/d' -e '/"serviceUrl"/a\    "cacheUrl": "https://vscode.blob.core.windows.net/gallery/index",' \
      -e 's|"itemUrl":.*|"itemUrl": "https://marketplace.visualstudio.com/items"|' \
      -e '/"linkProtectionTrustedDomains"/d' "$f"
    ok "Repo → MS Marketplace"
  fi
}

vscodium_prod_full(){
  local dst=${1:-/usr/share/vscodium/resources/app/product.json}
  [[ -f $dst ]] || die "Missing: $dst"
  local v work="/tmp/vp.$$" src bak
  src="${work}/product.json"
  bak="${dst}.backup.$(date +%s)"
  v=$("$JQ" -r '.version//empty' "$dst") || die "No version in $dst"
  cp "$dst" "$bak"
  dl "https://update.code.visualstudio.com/$v/linux-x64/stable" "${work}/c.tgz" || {
    rm -rf "$work"
    return 1
  }
  tar xf "${work}/c.tgz" -C "$work" --strip-components=3 VSCode-linux-x64/resources/app/product.json 2>/dev/null
  "$JQ" -s --argjson k "$(printf '%s\n' "${KEYS_PROD[@]}" | "$JQ" -R . | "$JQ" -s .)" \
    '.[0] as $d|.[1] as $s|$d+($s|with_entries(select(.key as $x|$k|index($x))))|.+{enableTelemetry:false,dataFolderName:".local/share/codium"}' \
    "$dst" "$src" >"${dst}.tmp" && mv "${dst}.tmp" "$dst"
  rm -rf "$work"
  ok "VSCodium Full Patch (backup: $bak)"
}

vscodium_restore(){
  local d=${1:-/usr/share/vscodium/resources/app/product.json}
  local -a blist=()
  local b
  mapfile -t blist < <(find "${d%/*}" -maxdepth 1 -name "${d##*/}.backup.*" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1)
  ((${#blist[@]})) || die "No backup found for $d"
  b=${blist[0]#* }
  cp -f "$b" "$d" && ok "Restored ← $b"
}

configure_privacy(){
  printf '%bConfiguring VSCode/VSCodium privacy settings...%b\n' "$Y" "$D"
  local changed=0
  local settings=(
    'telemetry.telemetryLevel;"off"'
    'telemetry.enableTelemetry;false'
    'telemetry.enableCrashReporter;false'
    'workbench.enableExperiments;false'
    'update.mode;"none"'
    'update.channel;"none"'
    'update.showReleaseNotes;false'
    'npm.fetchOnlinePackageInfo;false'
    'git.autofetch;false'
    'workbench.settings.enableNaturalLanguageSearch;false'
    'typescript.disableAutomaticTypeAcquisition;true'
    'workbench.experimental.editSessions.enabled;false'
    'workbench.experimental.editSessions.autoStore;false'
    'workbench.editSessions.autoResume;false'
    'workbench.editSessions.continueOn;false'
    'extensions.autoUpdate;false'
    'extensions.autoCheckUpdates;false'
    'extensions.showRecommendationsOnlyOnDemand;true'
  )
  for setting in "${settings[@]}"; do
    IFS=';' read -r prop val <<<"$setting"
    if vscode_json_set "$prop" "$val"; then
      printf '  %b %s\n' "${G}✓${D}" "$prop"
      ((changed++))
    else
      printf '  %b %s\n' "${Y}→${D}" "$prop"
    fi
  done
  ok "Privacy: $changed settings changed"
}

main(){
  local CP="/usr/lib/code/product.json" CD="/usr/share"
  case ${1:-} in
  xdg) xdg_patch ;;
  xdg-data)
    local f=${2:-/usr/share/vscodium/resources/app/product.json}
    sed -i 's|"dataFolderName": "[^"]*"|"dataFolderName": ".local/share/codium"|' "$f" && ok "DataFolder"
    ;;
  vscodium) repo_swap "${2:-}" 0 ;;
  vscodium-restore) repo_swap "${2:-}" 1 ;;
  vscodium-prod) vscodium_prod_full "${2:-}" ;;
  vscodium-prod-restore) vscodium_restore "${2:-}" ;;
  feat) json_op apply "${2:-$CP}" "${3:-$CD/code-features/patch.json}" "${4:-$CD/code-features/cache.json}" ;;
  feat-restore) json_op restore "${2:-$CP}" "${3:-$CD/code-features/patch.json}" "${4:-$CD/code-features/cache.json}" ;;
  feat-update) update_json "${2:-}" "${3:-./patch.json}" KEYS_PROD ;;
  mkt)
    json_op apply "${2:-$CP}" "${3:-$CD/code-marketplace/patch.json}" "${4:-$CD/code-marketplace/cache.json}"
    sign_fix node-ovsx-sign
    ;;
  mkt-restore)
    json_op restore "${2:-$CP}" "${3:-$CD/code-marketplace/patch.json}" "${4:-$CD/code-marketplace/cache.json}"
    sign_fix
    ;;
  mkt-update)
    # shellcheck disable=SC2034 # K used via nameref in update_json
    local -a K=(extensionsGallery extensionRecommendations keymapExtensionTips languageExtensionTips configBasedExtensionTips webExtensionTips virtualWorkspaceExtensionTips remoteExtensionTips extensionAllowedBadgeProviders extensionAllowedBadgeProvidersRegex msftInternalDomains linkProtectionTrustedDomains)
    update_json "${2:-}" "${3:-./patch.json}" K
    ;;
  privacy) configure_privacy ;;
  all)
    xdg_patch
    repo_swap "" 0
    json_op apply "$CP" "$CD/code-marketplace/patch.json" "$CD/code-marketplace/cache.json"
    json_op apply "$CP" "$CD/code-features/patch.json" "$CD/code-features/cache.json"
    sign_fix node-ovsx-sign
    configure_privacy
    ;;
  all-vscodium)
    xdg_patch
    vscodium_prod_full "${2:-}"
    configure_privacy
    ;;
  *)
    printf "Usage: %s {xdg|xdg-data|vscodium[-prod][-restore]|feat[-restore|-update]|mkt[-restore|-update]|privacy|all[-vscodium]}\n" "$0"
    exit 1
    ;;
  esac
}
main "$@"
