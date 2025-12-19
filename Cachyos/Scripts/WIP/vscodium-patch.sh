#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail; shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' D=$'\e[0m'
warn(){ printf '%b\n' "${Y}⚠${D} $*" >&2; }
ok(){ printf '%b\n' "${G}✓${D} $*"; }
die(){ printf '%b\n' "${R}✗${D} $*" >&2; exit 1; }
has(){ command -v -- "$1" &>/dev/null; }
user_home(){
  local u=${SUDO_USER:-${USER:-}}
  [[ -n $u ]] || die "No USER/SUDO_USER detected"
  local h
  h=$(getent passwd "$u" | cut -d: -f6 || true)
  [[ -n $h && -d $h ]] || h=$HOME
  [[ -n $h && -d $h ]] || die "Cannot resolve home for $u"
  printf '%s\n' "$h"
}
JQ=
has jaq && JQ=jaq || JQ=jq
has "$JQ" || die "Need jq/jaq"
keys_json(){ # bash array -> JSON array string
  local -n _kref=$1
  printf '%s\n' "${_kref[@]}" | "$JQ" -R . | "$JQ" -s .
}
dl(){
  local u=$1 o=$2
  mkdir -p "${o%/*}"
  if has aria2c; then
    aria2c -q --max-tries=3 --retry-wait=1 -d "${o%/*}" -o "${o##*/}" "$u"
  elif has curl; then
    curl -fsSL --retry 3 --http2 --tlsv1.2 "$u" -o "$o"
  elif has wget; then
    wget -qO "$o" "$u"
  else
    die "Need aria2c/curl/wget"
  fi
}
vscode_json_set(){
  local prop=$1 val=$2 home_dir
  has python3 || { warn "No python3: $prop"; return 1; }
  home_dir=$(user_home)
  python3 <<EOF
from pathlib import Path
import os, json, sys
property_name = ${prop!r}
target = json.loads(${val!r})
home_dir = ${home_dir!r}
settings_files = [
  f"{home_dir}/.config/Code/User/settings.json",
  f"{home_dir}/.var/app/com.visualstudio.code/config/Code/User/settings.json",
  f"{home_dir}/.config/VSCodium/User/settings.json",
  f"{home_dir}/.var/app/com.vscodium.codium/config/VSCodium/User/settings.json",
]
changed = 0
for sf in settings_files:
  file = Path(sf)
  if not file.exists():
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text("{}")
  content = file.read_text() or "{}"
  try:
    obj = json.loads(content)
  except json.JSONDecodeError:
    print(f"Invalid JSON in {sf}", file=sys.stderr)
    continue
  if obj.get(property_name) == target:
    continue
  obj[property_name] = target
  file.write_text(json.dumps(obj, indent=2))
  changed += 1
sys.exit(0 if changed > 0 else 1)
EOF
}
# NOTE: populate with the full key list from upstream; keep at least the core ones
KEYS_PROD=(
  nameShort nameLong applicationName dataFolderName serverDataFolderName
  darwinBundleIdentifier linuxIconName licenseUrl
  extensionAllowedProposedApi extensionEnabledApiProposals extensionKind
  extensionSyncedKeys extensionUntrustedWorkspacesSupport
  extensionsGallery extensionRecommendations keymapExtensionTips
  languageExtensionTips configBasedExtensionTips webExtensionTips
  virtualWorkspaceExtensionTips remoteExtensionTips
)
dl_extract_product(){
  local version=$1 out_json=$2 keys_json_str=$3 extra_patch=$4
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  printf "⬇ VSCode %s...\n" "$version"
  dl "https://update.code.visualstudio.com/${version}/linux-x64/stable" "$tmp/c.tgz"
  tar xf "$tmp/c.tgz" -C "$tmp" --strip-components=3 VSCode-linux-x64/resources/app/product.json 2>/dev/null \
    || die "Extract failed"
  "$JQ" -r --argjson k "$keys_json_str" "$extra_patch" "$tmp/product.json" >"$out_json"
}
xdg_patch(){
  local -a files=()
  mapfile -t files < <(
    find /usr/{lib/code*,share/applications} /opt/{visual-studio-code*,vscodium*} \
      -type f \( -name 'package.json' -o -name '*.desktop' \) ! -name '*-url-handler.desktop' 2>/dev/null
  )
  ((${#files[@]})) || { warn "No XDG files found"; return 0; }
  local f mime_added
  for f in "${files[@]}"; do
    case $f in
      *.desktop)
        mime_added=0
        if ! grep -qF "text/plain" "$f"; then
          sed -i 's/^\(MimeType=.*\);$/\1;text\/plain;/' "$f"
          ((mime_added++))
        fi
        if ! grep -qF "inode/directory" "$f"; then
          sed -i 's/^\(MimeType=.*\);$/\1;inode\/directory;/' "$f"
          ((mime_added++))
        fi
        ((mime_added)) && ok "$f (+${mime_added} MIME)" || ok "$f (current)" ;;
      */package.json)
        sed -i 's/"desktopName":[[:space:]]*"\([^"]*\)-url-handler\.desktop"/"desktopName": "\1.desktop"/' "$f" && ok "$f" ;;
    esac
  done
}
json_op(){
  local op=$1 prod=$2 patch=$3 cache=$4
  [[ -f $prod ]] || { warn "$prod missing"; return 1; }
  [[ -f $patch ]] || die "Patch missing: $patch"
  local tmp; tmp=$(mktemp)
  case $op in
    apply)
      [[ -f $cache ]] || printf '{}' >"$cache"
      "$JQ" -s '
        .[0] as $b | .[1] as $p |
        ($b|to_entries|map(select(.key as $k | $p|has($k)))|from_entries) as $c |
        ($b+$p) as $n | {p:$n,c:$c}
      ' "$prod" "$patch" >"$tmp" || die "jq apply failed"
      "$JQ" -r .p "$tmp" >"$prod"
      "$JQ" -r .c "$tmp" >"$cache"
      rm -f "$tmp"
      ok "Applied → $prod" ;;
    restore)
      [[ -f $cache ]] || die "Cache missing: $cache"
      "$JQ" -s '
        .[0] as $b | .[1] as $p | .[2] as $c |
        ($b|to_entries|map(select(.key as $k | ($p|has($k))|not))|from_entries) + $c
      ' "$prod" "$patch" "$cache" >"$tmp" || die "jq restore failed"
      mv "$tmp" "$prod"
      ok "Restored → $prod" ;;
  esac
}
update_json(){
  local v=$1 out=$2
  local -n kref="$3"
  [[ -n $v ]] || die "Version required"
  local kj; kj=$(keys_json kref)
  dl_extract_product "$v" "$out" "$kj" '
    reduce $k[] as $x ({}; . + {($x): (getpath($x|split("."))?)}) | . + {enableTelemetry:false}
  '
  ok "Updated → $out"
  [[ -f ./PKGBUILD ]] && has updpkgsums && updpkgsums ./PKGBUILD &>/dev/null || :
}
sign_fix(){
  local f="/usr/lib/code/out/vs/code/electron-utility/sharedProcess/sharedProcessMain.js" old=${1:-@vscode/vsce-sign} new=${2:-node-ovsx-sign}
  [[ -f $f ]] && sed -i "s|import(\"${old}\")|import(\"${new}\")|g" "$f" && ok "Sign fix: $new"
}
repo_swap(){
  local f=${1:-/usr/share/vscodium/resources/app/product.json} mode=${2:-0}
  [[ -f $f ]] || die "No product.json: $f"
  if ((mode)); then
    sed -i \
      -e 's|"serviceUrl": *"[^"]*"|"serviceUrl": "https://open-vsx.org/vscode/gallery",|' \
      -e '/"cacheUrl"/d' \
      -e 's|"itemUrl": *"[^"]*"|"itemUrl": "https://open-vsx.org/vscode/item"|' \
      -e '/"linkProtectionTrustedDomains"/d' \
      "$f"
    ok "Repo → Open-VSX"
  else
    sed -i \
      -e 's|"serviceUrl": *"[^"]*"|"serviceUrl": "https://marketplace.visualstudio.com/_apis/public/gallery",|' \
      -e '/"cacheUrl"/d' \
      -e '/"serviceUrl"/a\    "cacheUrl": "https://vscode.blob.core.windows.net/gallery/index",' \
      -e 's|"itemUrl": *"[^"]*"|"itemUrl": "https://marketplace.visualstudio.com/items",|' \
      "$f"
    ok "Repo → MS Marketplace"
  fi
}
vscodium_prod_full(){
  local dst=${1:-/usr/share/vscodium/resources/app/product.json}
  [[ -f $dst ]] || die "Missing: $dst"
  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  local v bak src="$tmp/product.json"
  v=$("$JQ" -r '.version//empty' "$dst") || die "No version in $dst"
  bak="${dst}.backup.$(date +%s)"
  cp "$dst" "$bak"
  dl "https://update.code.visualstudio.com/$v/linux-x64/stable" "$tmp/c.tgz"
  tar xf "$tmp/c.tgz" -C "$tmp" --strip-components=3 VSCode-linux-x64/resources/app/product.json 2>/dev/null \
    || die "Extract failed"
  "$JQ" -s --argjson k "$(keys_json KEYS_PROD)" '
    .[0] as $d | .[1] as $s |
    $d + ($s|with_entries(select(.key as $x | $k|index($x)))) + {enableTelemetry:false, dataFolderName:".vscode-oss"}
  ' "$dst" "$src" >"$tmp/out.json" || die "jq merge failed"
  mv "$tmp/out.json" "$dst"
  ok "VSCodium Full Patch (backup: $bak)"
}
vscodium_restore(){
  local d=${1:-/usr/share/vscodium/resources/app/product.json} -a blist=() b
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
  )
  local setting prop val
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
      sed -i 's|"dataFolderName": "[^"]*"|"dataFolderName": ".local/share/codium"|' "$f" && ok "DataFolder" ;;
    vscodium) repo_swap "${2:-}" 0 ;;
    vscodium-restore) repo_swap "${2:-}" 1 ;;
    vscodium-prod) vscodium_prod_full "${2:-}" ;;
    vscodium-prod-restore) vscodium_restore "${2:-}" ;;
    feat) json_op apply "${2:-$CP}" "${3:-$CD/code-features/patch.json}" "${4:-$CD/code-features/cache.json}" ;;
    feat-restore) json_op restore "${2:-$CP}" "${3:-$CD/code-features/patch.json}" "${4:-$CD/code-features/cache.json}" ;;
    feat-update) update_json "${2:-}" "${3:-./patch.json}" KEYS_PROD ;;
    mkt)
      json_op apply "${2:-$CP}" "${3:-$CD/code-marketplace/patch.json}" "${4:-$CD/code-marketplace/cache.json}"
      sign_fix node-ovsx-sign ;;
    mkt-restore)
      json_op restore "${2:-$CP}" "${3:-$CD/code-marketplace/patch.json}" "${4:-$CD/code-marketplace/cache.json}"
      sign_fix ;;
    mkt-update)
      local -a K=(
        extensionsGallery extensionRecommendations keymapExtensionTips languageExtensionTips
        configBasedExtensionTips webExtensionTips virtualWorkspaceExtensionTips
        remoteExtensionTips extensionEnabledApiProposals extensionAllowedProposedApi
      )
      update_json "${2:-}" "${3:-./patch.json}" K ;;
    privacy) configure_privacy ;;
    all)
      xdg_patch
      repo_swap "" 0
      json_op apply "$CP" "$CD/code-marketplace/patch.json" "$CD/code-marketplace/cache.json"
      json_op apply "$CP" "$CD/code-features/patch.json" "$CD/code-features/cache.json"
      sign_fix node-ovsx-sign
      configure_privacy ;;
    all-vscodium)
      xdg_patch
      vscodium_prod_full "${2:-}"
      configure_privacy ;;
    *)
      printf "Usage: %s {xdg|xdg-data|vscodium[-prod][-restore]|feat[-restore|-update]|mkt[-restore|-update]|privacy|all[-vscodium]}\n" "$0"
      exit 1; ;;
  esac
}
main "$@"
