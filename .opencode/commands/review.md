---
description: Diff-aware code review for changed shell scripts — security, correctness, style
agent: code
---

Review the following staged/unstaged changes against the Linux-OS bash standards.

Diff to review:
!`git diff HEAD`

For each changed `.sh` file evaluate:

**Security**
- Command injection: unquoted variables passed to `eval`, `bash -c`, or shell builtins
- Path traversal: user-supplied paths not validated with `[[ $path =~ ^[[:alnum:]/_.-]+$ ]]`
- Hardcoded credentials or tokens

**Correctness**
- Missing `set -Eeuo pipefail` or `shopt -s nullglob globstar extglob dotglob`
- Missing `trap` for `EXIT`, `ERR`, `INT TERM`
- Parsing `ls` output, using backticks, using `eval`, `for x in $(cmd)`
- Unquoted variables outside intentional glob/split contexts

**Performance**
- Subshells where `${var##*/}` / `${var%/*}` / `${var,,}` suffice
- `cat file | cmd` instead of `cmd < file` or `$(<file)`
- Missing `-P$(nproc)` for parallelizable loops over many items

**Style**
- `echo` instead of `printf`
- Missing `has()` / fallback chains for external tools
- Color palette not using trans flag colors (LBLU/PNK/BWHT)

Output findings as: `file:line — severity — description — fix`
