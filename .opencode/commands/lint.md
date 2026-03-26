---
description: Run shellcheck + shfmt on all shell scripts and report violations
agent: code
---

Run the full lint and format suite on all shell scripts in this repository.

Current repo state:
!`git status --short`

Execute:
```bash
./lint-format.sh
```

If `lint-format.sh` is missing, run tools directly:
```bash
fd -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs shellcheck --severity=style
fd -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs shfmt -i 2 -ci -sr -d
```

Report all violations grouped by file. For each violation include:
- File path and line number
- ShellCheck rule ID and message
- Suggested fix using pure-bash idioms where possible (no unnecessary subshells)
