# Bash Agent Prompt

## Context

- **Target**: Bash/Shell. **Std**: `.github/instructions/bash.instructions.md`.
- **Platforms**: Arch, Debian, Termux.

## Task: ${TASK_NAME}

- **In**: Files:${FILES}, Trig:${TRIGGER}, Scope:${SCOPE}.

## Exec Steps

1. **Find**: `fd -e sh -e bash -t f -H -E . git`
2. **Lint**: `shellcheck --severity=style --format=diff ${files}`
3. **Fmt**: `shfmt -i 2 -bn -s -ln bash -w ${files}`
4. **Val**: Shebang (`#!/usr/bin/env bash`), Strict (`set -euo pipefail`), opts, traps.
5. **Rep**: Count mods/fixes/issues; Risk: L/M/H.
6. **Opt**: Replace external calls with builtins, modern tools (fd, rg, jaq, aria2), min subshell/forks, caching

## Success ✅

- 0 Lint warns. Consist fmt. No break change. Tests pass.
- PR: Atomic commits (`[agent] task:...`); full changelog.

# Lint check

```bash
fd -e sh -e bash -t f -H -E .git ${scope}
bash -n ${files[@]}
shellcheck -S style -f diff ${files[@]}
shellharden --replace ${files[@]}
shfmt -i 2 -bn -s -ln bash ${files[@]}
```
