# Claude Operating Manual

## Prime Directives
1. **User Primacy:** User commands override all rules.
2. **Factual Verification:** Use tools for versions/APIs. Never guess.
3. **Surgical Modification:** Edit > Create. Minimal line changes. Preserve existing style/logic.
4. **Debt-First:** Remove clutter/deps before adding. Subtraction > Addition.
5. **Autonomous Execution:** Act immediately. Minimize confirmations unless destructive.

## Communication
- **Tone:** Blunt, factual, precise, concise. Technical English.
- **Format:** 2-space indent. No filler. Strip U+202F/U+200B/U+00AD.
- **Output:** Result-first (`Result ∴ Cause`). Group by domain. Lists ≤7 items.
- **Abbrev:** cfg, impl, deps, val, auth, opt, Δ.

### Symbols
→ leads to | ⇒ converts | « / » precedes/follows | ∴ / ∵ therefore/because | ✅ / ❌ success/fail | ⚡ performance | 🛡️ security | 🧪 testing | 📦 deployment | 🔍 analysis

## Bash Standards
**Targets:** Arch/Wayland (primary), Debian/Raspbian (secondary), Termux.
```bash
#!/usr/bin/env bash
set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'
export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
has(){ command -v "$1" &>/dev/null; }
```

**Idioms (Strict):**
- Tests: `[[ ... ]]`. Regex: `[[ $var =~ ^regex$ ]]`
- Loops: `while IFS= read -r line; do ...; done < <(cmd)`. **NO** `for x in $(ls)`
- Output: `printf` over `echo`. Capture: `ret=$(fn)`
- Functions: `name(){ ... }` (no `function` kw). Nameref: `local -n ref=name`
- Arrays: `mapfile -t`. Assoc: `declare -A cfg=([key]=val)`
- **Forbidden:** Parsing `ls`, `eval`, backticks, unnecessary subshells

**Quote:** Always quote variables unless intentional glob/split.

**Privilege & Packages:**
- Escalation: `sudo-rs`→`sudo`→`doas` (store in `PRIV_CMD`)
- Install: `paru`→`yay`→`pacman` (Arch); `apt` (Debian)
- Check first: `pacman -Q`, `flatpak list`, `cargo install --list`

## Tool Hierarchy (Fallbacks Required)
| Task | Primary | Fallback Chain |
|:---|:---|:---|
| Find | `fd` | `fdfind`→`find` |
| Grep | `rg` | `grep -E` (prefer `-F` for literals) |
| View | `bat` | `cat` |
| Edit | `sd` | `sed -E` |
| Nav | `zoxide` | `cd` |
| Web | `aria2` | `curl`→`wget2`→`wget` |
| JSON | `jaq` | `jq` |
| Parallel | `rust-parallel` | `parallel`→`xargs -r -P$(nproc)` |

## Performance
**Measure first. Optimize hot paths.**
- **General:** Batch I/O. Cache computed values. Early returns.
- **Bash:** Minimize forks/subshells. Use builtins. Anchor regexes. Literal search (grep -F, rg -F).
- **Frontend:** Minimize DOM Δ. Stable keys in lists. Lazy load assets/components.
- **Backend:** Async I/O. Connection pooling. Avoid N+1 queries. Cache hot data (Redis).

## Protected Files
**Do NOT modify unless explicitly requested:**
- `pacman.conf`, `makepkg.conf`, `/etc/sysctl.d/`, `.zshrc`, `.gitconfig`

**Safe zones:** Shell scripts, `.config/`, docs, workflows.

## Workflow (TDD & Atomic)
1. **Red:** Write/verify failing test.
2. **Green:** Minimal logic to pass.
3. **Refactor:** Optimize (subtractive design).
4. **Commit:** Single logical unit. Tests pass. No lint errors.
   - Never mix structural (format) and behavioral changes.

## File Operations
- **Edit over create:** Use `str_replace` for existing files.
- **Validation:** Run shellcheck, verify bash syntax before saving.
- **Preserve:** Maintain existing indent, comment style, logic flow.
