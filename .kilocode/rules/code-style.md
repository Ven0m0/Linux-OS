# Code Style Rules

## Shell Script Formatting

- Indent: 2 spaces (never tabs in `.sh` files)
- Max line length: 120 characters
- Line endings: LF only
- Final newline: required
- Trailing whitespace: forbidden
- Shfmt invocation: `shfmt -i 2 -ci -sr` (case indent, space redirects)

## Shebang

Every shell script MUST start with `#!/usr/bin/env bash`, never `#!/bin/bash`.

## Strict Mode (mandatory first 4 lines after shebang)

```bash
set -Eeuo pipefail
shopt -s nullglob globstar extglob dotglob
IFS=$'\n\t'
export LC_ALL=C LANG=C
```

## Naming Conventions

- Functions: `snake_case` without `function` keyword — `foo(){ ... }`
- Constants/colors: `UPPER_CASE` — `LBLU`, `PNK`, `DEF`
- Local variables: `snake_case` with `local` declaration
- Associative config array: always named `cfg` — `declare -A cfg=([key]=val)`
- Output namerefs: prefixed with `_` to avoid collision — `local -n _out=$1`

## Printf Over Echo

- Use `printf '%s\n'` not `echo` — `echo` behavior varies across implementations
- Exception: `xecho(){ printf '%b\n' "$*"; }` wrapper is acceptable

## String Operations

Use parameter expansion over subshells:

| Task | Correct | Forbidden |
|------|---------|-----------|
| Basename | `${f##*/}` | `$(basename "$f")` |
| Dirname | `${f%/*}` | `$(dirname "$f")` |
| Extension | `${f##*.}` | `$(echo "$f" \| rev \| cut -d. -f1 \| rev)` |
| Lowercase | `${s,,}` | `$(echo "$s" \| tr A-Z a-z)` |
| Strip suffix | `${s%.sh}` | `$(echo "$s" \| sed 's/\.sh$//')` |

## YAML / JSON / Workflow Files

- Indent: 2 spaces
- Max line length: 120 characters

## Markdown

- Max line length: 88 characters
- Trailing whitespace: allowed (for line breaks)
