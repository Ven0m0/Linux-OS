#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR external-sources=true
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C; IFS=$'\n\t'
# 1. Centralize Flags
# -s -w: Strip debug info (smaller binary)
# -trimpath: Remove file system paths (reproducible builds)
LINKER_FLAGS="-s -w -trimpath -modcacherw"
export GOGC=200 GOMAXPROCS="$(nproc)"
export GOFLAGS="-ldflags=$LINKER_FLAGS"
# 2. Helper function to check/install tools (Avoids re-installing if present)
ensure_tool(){
  local cmd="$1" pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    printf "Installing %s...\n" "$cmd"
    go install "$pkg@latest"
  fi
}

# 3. Disable telemetry once
go telemetry off 2>/dev/null || :

# 4. Install tools only if missing
ensure_tool "betteralign" "github.com/dkorunic/betteralign/cmd/betteralign"
ensure_tool "goptimizer" "github.com/johnsiilver/goptimizer"

# 5. Run Optimizations
echo "Running struct alignment..."
betteralign -apply -fix -generated_files ./...

echo "Running binary optimizer..."
# Pass the flags explicitly to goptimizer as it may not inherit GOFLAGS env perfectly
goptimizer --goflags="--ldflags=$LINKER_FLAGS"
