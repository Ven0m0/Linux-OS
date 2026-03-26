# Code Mode Constraints

## Diff Size Limits

- Single commit: ≤200 lines changed per script file
- Never mix structural (formatting) and behavioral changes in the same commit
- If a refactor touches >5 files, split into multiple targeted commits

## Refactor Scope

- Edit the minimum lines needed to fix the bug or add the feature
- Do not reformat lines you didn't change — CI auto-formats on push
- Do not add docstrings, type annotations, or comments to unchanged code
- Do not add error handling for scenarios that cannot occur (trust `set -Eeuo pipefail`)

## Forbidden Patterns in Code Mode

Never introduce:
- New files named `lib.sh`, `common.sh`, `utils.sh` — standalone scripts only
- `source` or `.` commands importing external files (breaks curl-pipe use case)
- `eval` in any form
- `function` keyword (`foo(){ ... }` not `function foo { ... }`)
- Backtick command substitution
- `echo` for structured output (use `printf`)
- `for x in $(find ...)` or `for x in $(ls ...)`
- `cat file | cmd` when `cmd < file` works
- `sudo sh -c "$var"` with interpolated variables
- Hardcoded paths to `/home/user` or any specific username

## Subtractive Design

Before adding a helper function, check if the logic can be expressed with:
1. A parameter expansion (`${var//pat/rep}`, `${var##*/}`, etc.)
2. An existing helper already inlined in the script
3. A single `mapfile` + loop

Three similar lines of code is better than a premature abstraction.

## Commit Type Enforcement

- `fix`: must change observable behavior (not just formatting)
- `refactor`: must NOT change observable behavior
- `chore`: CI, docs, config only — no `.sh` logic changes
- `perf`: must include a before/after `hyperfine` result in commit body
