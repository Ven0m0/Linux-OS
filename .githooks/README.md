# Git Hooks

## Installation

To use these hooks, configure git to use this directory:

```bash
git config core.hooksPath .githooks
```

## Pre-commit Hook

The pre-commit hook performs automated quality and performance checks:

### Checks Performed

1. **ShellCheck** - Lints shell scripts for errors
2. **Performance Anti-patterns** - Detects common performance issues:
   - Inefficient `tr` usage (suggest `${var,,}`)
   - `basename`/`dirname` usage (suggest parameter expansion)
   - `sudo sh -c echo` pattern (suggest `printf | sudo tee`)
   - `$(cat file)` usage (suggest `$(<file)`)
3. **Syntax Check** - Validates bash syntax with `bash -n`
4. **Formatting** - Checks code formatting with `shfmt` (if available)

### Bypassing Checks

If you need to bypass the pre-commit checks:

```bash
git commit --no-verify
```

Use this sparingly and only when necessary.

## Performance Guidelines

See `docs/PERFORMANCE.md` for detailed performance best practices.
