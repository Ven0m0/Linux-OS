#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob
IFS=$'\n\t'; export LC_ALL=C LANG=C

# Plugin shim for @trinhnv1205/optimize
# Usage: source this, then call ven0mo_register_menu to add entries;
# requires Cachyos/Scripts/Android/android-optimize.sh on PATH.

V_OPT_BIN="${V_OPT_BIN:-android-optimize.sh}"

ven0mo_actions(){
  cat <<'EOF'
1) Ven0mo Full Optimize (device-all)
2) Ven0mo Monolith (everything-profile)
3) Ven0mo Cache Clean
4) Ven0mo Index .nomedia
5) Ven0mo WhatsApp Clean
EOF
}

ven0mo_handle(){
  case "$1" in
    1) "$V_OPT_BIN" device-all;;
    2) "$V_OPT_BIN" monolith everything-profile;;
    3) "$V_OPT_BIN" cache-clean;;
    4) "$V_OPT_BIN" index-nomedia;;
    5) "$V_OPT_BIN" wa-clean;;
    *) return 1;;
  esac
}

# Optional helper to append to an external menu implementation
ven0mo_register_menu(){
  : "${MENU_ADD_ITEM:=}"
  : "${MENU_SET_HANDLER:=}"
  command -v "$V_OPT_BIN" &>/dev/null || { printf 'android-optimize.sh not found in PATH\n' >&2; return 1; }
  if [[ -n "${MENU_ADD_ITEM:-}" && -n "${MENU_SET_HANDLER:-}" ]]; then
    MENU_ADD_ITEM "Ven0mo Optimize" "$(ven0mo_actions)"
    MENU_SET_HANDLER "Ven0mo Optimize" ven0mo_handle
  fi
}