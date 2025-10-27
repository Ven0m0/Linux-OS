#!/bin/bash
#
# prepare-for-revanced
# Extract universal APK from a split .apks archive, align, and sign.
#

prepare_for_revanced() {
  local SCRIPT_NAME="prepare-for-revanced"
  local DEBUG_KEYSTORE="$HOME/.android/debug.keystore"
  local DEBUG_KEY_ALIAS="androiddebugkey"
  local DEBUG_KEY_PASS="android"
  local OUTPUT_FILE=""
  local APKS_ARCHIVE=""

  print_usage() {
    echo "Usage: $SCRIPT_NAME [options] <app.apks>"
    echo ""
    echo "Options:"
    echo "  -o, --output <FILE>   Output universal APK path."
    echo "  -h, --help            Show this help message."
  }

  log() { echo " INFO: $1"; }
  log_error() { echo " ERROR: $1" >&2; }

  # --- Parse args ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -o | --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h | --help)
      print_usage
      return 0
      ;;
    *)
      APKS_ARCHIVE="$1"
      shift
      ;;
    esac
  done

  if [[ -z $APKS_ARCHIVE ]]; then
    log_error "No .apks file provided."
    print_usage
    return 1
  fi

  if [[ -z $OUTPUT_FILE ]]; then
    local base_name
    base_name=$(basename "$APKS_ARCHIVE" .apks)
    OUTPUT_FILE="${base_name}-universal.apk"
  fi

  # --- Check deps ---
  local dependencies=("unzip" "zipalign" "apksigner" "keytool")
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found."
      return 1
    fi
  done

  # --- Keystore check ---
  if [[ ! -f $DEBUG_KEYSTORE ]]; then
    log "Generating debug keystore..."
    mkdir -p "$(dirname "$DEBUG_KEYSTORE")"
    keytool -genkey -v -keystore "$DEBUG_KEYSTORE" \
      -alias "$DEBUG_KEY_ALIAS" -keypass "$DEBUG_KEY_PASS" \
      -storepass "$DEBUG_KEY_PASS" -keyalg RSA -keysize 2048 \
      -validity 10000 -dname "CN=Android Debug,O=Android,C=US" || return 1
  fi

  # --- Workspace ---
  local WORKSPACE
  WORKSPACE=$(mktemp -d -t revanced_prep_XXXXXX)
  trap 'rm -rf "$WORKSPACE"' EXIT

  log "Created workspace $WORKSPACE"

  # --- Extract universal APK ---
  log "Extracting universal APK from $APKS_ARCHIVE..."
  unzip -j "$APKS_ARCHIVE" universal.apk -d "$WORKSPACE" || {
    log_error "universal.apk not found inside $APKS_ARCHIVE"
    return 1
  }

  # --- Zipalign ---
  log "Aligning APK..."
  zipalign -p 4 "$WORKSPACE/universal.apk" "$WORKSPACE/aligned.apk" || return 1

  # --- Sign ---
  log "Signing APK..."
  apksigner sign \
    --ks "$DEBUG_KEYSTORE" \
    --ks-key-alias "$DEBUG_KEY_ALIAS" \
    --ks-pass "pass:$DEBUG_KEY_PASS" \
    --out "$OUTPUT_FILE" \
    "$WORKSPACE/aligned.apk" || return 1

  log "SUCCESS: Final APK saved at $(realpath "$OUTPUT_FILE")"
  return 0
}

# Run if called directly
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  prepare_for_revanced "$@"
fi
#!/bin/bash
#
# prepare-for-revanced
# Extract universal APK from a split .apks archive, align, and sign.
#

prepare_for_revanced() {
  local SCRIPT_NAME="prepare-for-revanced"
  local DEBUG_KEYSTORE="$HOME/.android/debug.keystore"
  local DEBUG_KEY_ALIAS="androiddebugkey"
  local DEBUG_KEY_PASS="android"
  local OUTPUT_FILE=""
  local APKS_ARCHIVE=""

  print_usage() {
    echo "Usage: $SCRIPT_NAME [options] <app.apks>"
    echo ""
    echo "Options:"
    echo "  -o, --output <FILE>   Output universal APK path."
    echo "  -h, --help            Show this help message."
  }

  log() { echo " INFO: $1"; }
  log_error() { echo " ERROR: $1" >&2; }

  # --- Parse args ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -o | --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h | --help)
      print_usage
      return 0
      ;;
    *)
      APKS_ARCHIVE="$1"
      shift
      ;;
    esac
  done

  if [[ -z $APKS_ARCHIVE ]]; then
    log_error "No .apks file provided."
    print_usage
    return 1
  fi

  if [[ -z $OUTPUT_FILE ]]; then
    local base_name
    base_name=$(basename "$APKS_ARCHIVE" .apks)
    OUTPUT_FILE="${base_name}-universal.apk"
  fi

  # --- Check deps ---
  local dependencies=("unzip" "zipalign" "apksigner" "keytool")
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command '$cmd' not found."
      return 1
    fi
  done

  # --- Keystore check ---
  if [[ ! -f $DEBUG_KEYSTORE ]]; then
    log "Generating debug keystore..."
    mkdir -p "$(dirname "$DEBUG_KEYSTORE")"
    keytool -genkey -v -keystore "$DEBUG_KEYSTORE" \
      -alias "$DEBUG_KEY_ALIAS" -keypass "$DEBUG_KEY_PASS" \
      -storepass "$DEBUG_KEY_PASS" -keyalg RSA -keysize 2048 \
      -validity 10000 -dname "CN=Android Debug,O=Android,C=US" || return 1
  fi

  # --- Workspace ---
  local WORKSPACE
  WORKSPACE=$(mktemp -d -t revanced_prep_XXXXXX)
  trap 'rm -rf "$WORKSPACE"' EXIT

  log "Created workspace $WORKSPACE"

  # --- Extract universal APK ---
  log "Extracting universal APK from $APKS_ARCHIVE..."
  unzip -j "$APKS_ARCHIVE" universal.apk -d "$WORKSPACE" || {
    log_error "universal.apk not found inside $APKS_ARCHIVE"
    return 1
  }

  # --- Zipalign ---
  log "Aligning APK..."
  zipalign -p 4 "$WORKSPACE/universal.apk" "$WORKSPACE/aligned.apk" || return 1

  # --- Sign ---
  log "Signing APK..."
  apksigner sign \
    --ks "$DEBUG_KEYSTORE" \
    --ks-key-alias "$DEBUG_KEY_ALIAS" \
    --ks-pass "pass:$DEBUG_KEY_PASS" \
    --out "$OUTPUT_FILE" \
    "$WORKSPACE/aligned.apk" || return 1

  log "SUCCESS: Final APK saved at $(realpath "$OUTPUT_FILE")"
  return 0
}

# Run if called directly
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  prepare_for_revanced "$@"
fi
