#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C
IFS=$'\n\t'
USER="${USER:-$(id -un)}"
export HOME="/home/${SUDO_USER:-$USER}"; sync
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#─────────────────────────────────────────
cd -- "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && echo "${PWD:-$(pwd)}")"

#–– Helpers
has(){ command -v -- "$1" &>/dev/null; }
hasname(){ local x; x=$(type -Pf -- "$1") && printf '%s\n' "${x##*/}"; }
xcho(){ printf '%s\n' "$*" 2>/dev/null; }
xecho(){ printf '%b\n' "$*"$'\e[0m' 2>/dev/null; }

# Fully safe optimal privelege tool
suexec="$(command -v sudo-rs 2>/dev/null || command -v sudo 2>/dev/null || command -v doas 2>/dev/null || :)"
[[ "${suexec:-}" == */sudo-rs || "${suexec:-}" == */sudo ]] && "$suexec" -v || :
suexec="${suexec:-sudo}"
if ! command -v "$suexec" &>/dev/null; then
  xcho "No valid privilege escalation tool found (sudo-rs, sudo, doas)." >&2; exit 1
fi

dname(){ local p=${1:-.}; [[ $p != *[!/]* ]] && { printf '/\n'; return; }; p=${p%${p##*[!/]}}; [[ $p != */* ]] && { printf '.\n'; return; }; p=${p%/*}; p=${p%${p##*[!/]}}; printf '%s\n' "${p:-/}"; }
bname(){ local t=${1%${1##*[!/}]}; t=${t##*/}; [[ $2 && $t == *"$2" ]] && t=${t%$2}; printf '%s\n' "${t:-/}"; }
regex(){ [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}" }
date(){ local x="${1:-%d/%m/%y-%R}"; printf "%($x)T\n" '-1'; }
fcat(){ printf '%s\n' "$(<"${1}")"; }

