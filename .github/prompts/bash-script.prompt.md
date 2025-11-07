---
name: Canonical Bash Script Template
description: The baseline template for all new Bash scripts, incorporating best practices for strictness, safety, and utility.
---

```bash
#!/usr/bin/env bash
#
# DESCRIPTION: [Brief, one-line description of the script's purpose]

# -- Strict Mode & Globals --
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD" || exit 1

# -- Color & Style --
BLK=$'\e[30m' RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' MGN=$'\e[35m' CYN=$'\e[36m' WHT=$'\e[37m'
LBLU=$'\e[38;5;117m' PNK=$'\e[38;5;218m' BWHT=$'\e[97m'
DEF=$'\e[0m' BLD=$'\e[1m'

# -- Core Helpers --
has(){ command -v -- "$1" &>/dev/null; }

# -- Tooling Shims --
FD_CMD=${FD_CMD:-$(command -v fd || command -v fdfind || echo "find")}
RG_CMD=${RG_CMD:-$(command -v rg || echo "grep")}
BAT_CMD=${BAT_CMD:-$(command -v bat || echo "cat")}

# -- Entrypoint --
main "$@"
```
