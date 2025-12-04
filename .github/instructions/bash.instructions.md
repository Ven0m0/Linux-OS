---
applyTo: '**/*.{sh,bash}'
description: 'Automated maintenance, linting, and formatting of Bash scripts and shell content following repository standards.'
---

# Bash Agent Instructions

## Purpose
Automated maintenance, linting, and formatting of Bash scripts and shell content following repository standards defined in `. github/instructions/bash.instructions.md`.

## Core Responsibilities

### 1. Code Quality Enforcement
- Run `shellcheck --severity=style` on all `. sh` files
- Format with `shfmt -i 2 -ci -sr`
- Optional hardening with `shellharden --replace`
- Zero warnings policy

### 2. Standards Compliance
- Verify shebang: `#!/usr/bin/env bash`
- Confirm strict mode: `set -Eeuo pipefail`
- Check shell options: `shopt -s nullglob globstar extglob dotglob`
- Validate `IFS=$'\n\t'` and `export LC_ALL=C LANG=C`

### 3. Idiom Verification
- Bash-native constructs: arrays, `mapfile -t`, `[[ ... ]]`, parameter expansion
- No forbidden patterns: `ls` parsing, `eval`, backticks
- Prefer builtins over external commands
- Proper quoting: variables quoted unless intentional glob/split

### 4. Tool Preferences
- Modern tools with fallbacks: `fd`/`find`, `rg`/`grep`, `bat`/`cat`, `sd`/`sed`
- Graceful degradation when tools missing
- No hard failures for optional tools

### 5. Security & Safety
- Validate privilege escalation: `sudo-rs` → `sudo` → `doas`
- Check cleanup traps: EXIT, ERR, INT, TERM
- Verify `mktemp` usage for temp files/dirs
- Ensure proper error handling with line numbers

## Automated Fixes

### Auto-fixable
- Formatting (shfmt)
- Common shellcheck warnings (SC2086, SC2046, SC2006)
- Trailing whitespace
- Missing final newline

### Require Manual Review
- Logic errors
- Security vulnerabilities
- Breaking API changes
- Platform-specific compatibility

## PR Creation Criteria
- Changes > 0 files
- All tests pass (if present)
- Zero linting errors
- Atomic commits (format separate from logic)

## Branch Naming
```
agent/lint/shellcheck-fixes-<short-sha>
agent/format/shfmt-cleanup-<short-sha>
agent/refactor/simplify-loops-<short-sha>
```

## Commit Messages
```
[agent] lint: fix shellcheck SC2086 in setup.sh
[agent] format: apply shfmt to all scripts
[agent] refactor: replace command substitution with mapfile
```

## Test Requirements
- Run existing test suites (bats-core if present)
- Platform compatibility: Arch and Debian/Raspbian
- Performance checks for critical paths (if benchmarks exist)

## Exclusions
- Don't modify: `.git/`, `node_modules/`, vendor code, submodules
- Preserve: intentional shellcheck directives, platform-specific workarounds
- Skip: generated files, third-party scripts marked as external

## Reporting
- Summary: files changed, warnings fixed, remaining issues
- Link to workflow run
- Attach logs (trimmed to 5MB)
- Risk assessment: LOW/MEDIUM/HIGH
- Test steps per platform

## Escalation
- Create issue for: unfixable errors, security concerns, breaking changes needed
- Request human review for: architectural changes, multi-file refactors, performance tradeoffs
