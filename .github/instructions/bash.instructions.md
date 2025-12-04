---
applyTo: '**/*.{sh,bash}'
description: 'Compressed standards for Bash scripts.'
---

# Bash Standards (Compressed)

## 🎯 Core Rules
- **Lint**: `shellcheck --severity=style` (0 warnings).
- **Fmt**: `shfmt -i 2 -bn -s -ln bash`.
- **Hardening**: `shellharden --replace` (optional).
- **Shebang**: `#!/usr/bin/env bash`.
- **Opts**: `set -euo pipefail`; `shopt -s nullglob globstar`.
- **Env**: `IFS=$'\n\t'`; `export LC_ALL=C LANG=C`.

## 🛠️ Idioms & Tools
- **Native**: Arrays, `mapfile -t`, `[[ ... ]]`, param exp (`${v:-def}`).
- **Avoid**: `ls` parsing, `eval`, backticks \`cmd\`, `expr`.
- **Pref**: `fd`>`find`, `rg`>`grep`, `jaq`>`jq`>`rust-parallel`>`parallel`>`xargs`
- **Quote**: Vars always quoted `"$var"` unless explicit split/glob.

##  Workflow
- **PR**: Clean lint, atomic commits (fmt != logic), tests pass.
- **Branch**: `agent/lint/...`, `agent/format/...`.
- **Msg**: `[agent] <type>: <desc>`.
- **Scope**: No vendored/generated code mod.
