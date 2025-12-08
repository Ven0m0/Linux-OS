# Copilot Instructions

## Control Hierarchy

1. User commands override all rules
2. Edit > Create (modify minimal lines)
3. Subtraction > Addition (remove before adding)
4. Align with existing patterns in repo

## Style & Format

- **Tone:** Blunt, factual, precise. No filler.
- **Format:** 2-space indent. Strip U+202F/U+200B/U+00AD.
- **Output:** Result-first. Lists ≤7 items.
- **Abbrev:** cfg=config, impl=implementation, deps=dependencies, val=validation, opt=optimization, Δ=change.

## Bash Standards

**Targets:** Arch/Wayland, Debian/Raspbian (Pi), Termux.

```bash
#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
has(){ command -v "$1" &>/dev/null; }
```

**Idioms:**

- Tests: `[[ ... ]]`. Regex: `[[ $var =~ ^pattern$ ]]`
- Loops: `while IFS= read -r line; do ...; done < <(cmd)`
- Output: `printf` over `echo`. Capture: `ret=$(fn)`
- Functions: `name(){ local var; ... }`. Nameref: `local -n ref=var`
- Arrays: `mapfile -t arr < <(cmd)`. Assoc: `declare -A map=([k]=v)`
- **Never:** Parse `ls`, `eval`, backticks, unnecessary subshells

**Quote:** Always quote vars unless intentional glob/split.

## Tool Preferences

fd→fdfind→find | rg→grep | bat→cat | sd→sed | aria2→curl→wget | jaq→jq | rust-parallel→parallel→xargs

## Perf Patterns

- Minimize forks/subshells. Use builtins. Batch I/O.
- Frontend: Minimize DOM Δ. Stable keys. Lazy load.
- Backend: Async I/O. Connection pool. Cache hot data.
- Anchor regexes. Prefer literal search (grep -F, rg -F).

## Privilege & Packages

- Escalation: `sudo-rs`→`sudo`→`doas` (store in `PRIV_CMD`)
- Install: `paru`→`yay`→`pacman` (Arch); `apt` (Debian)
- Check before install: `pacman -Q`, `flatpak list`, `cargo install --list`
