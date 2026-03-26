---
description: Scaffold a new shell script conforming to the Linux-OS template
agent: code
---

Create a new shell script at: $1
Purpose: $2

Generate the script using the canonical template from AGENTS.md:

Requirements:
- `#!/usr/bin/env bash` shebang
- `set -Eeuo pipefail` + `shopt -s nullglob globstar extglob dotglob`
- `IFS=$'\n\t'` + `export LC_ALL=C LANG=C`
- Trans flag color palette: `LBLU PNK BWHT DEF BLD`
- Core helpers: `has()` `log()` `warn()` `err()` `die()` `dbg()`
- `pm_detect()` if the script touches packages
- Tool detection with fallbacks (`FD` `RG` `BAT`)
- `WORKDIR=$(mktemp -d)` + `cleanup()` trap on EXIT
- `trap 'on_err $LINENO' ERR` + `trap ':' INT TERM`
- `declare -A cfg` config array with `dry_run debug quiet assume_yes`
- `run()` wrapper for dry-run support
- `parse_args()` with `-q -v -y -h --version` flags
- `main()` entry point

Place the new file at `$1` and immediately run:
```bash
shellcheck --severity=style "$1"
shfmt -i 2 -ci -sr -d "$1"
```

Fix any violations before presenting the file.
