---
description: Run shellcheck on a specific file and explain each warning
agent: code
---

Target file: $ARGUMENTS

Run shellcheck on the specified file:
```bash
shellcheck --severity=style $ARGUMENTS
```

For each warning:
1. Quote the offending line
2. Explain the risk in one sentence
3. Provide the corrected line using pure-bash idioms (no unnecessary subshells)

After all warnings, check if the file conforms to the script template in AGENTS.md:
- Has `set -Eeuo pipefail` + shopt flags
- Has `IFS=$'\n\t'` + `LC_ALL=C`
- Has `trap` for EXIT/ERR/INT TERM
- Uses `printf` not `echo`
- Has `has()` helper
