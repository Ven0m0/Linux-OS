# Implementation Plan
_Generated: 2026-03-21 · 4 tasks · Est. S–L LOC delta_

## Legend
<!-- severity: 🔴 critical 🟠 high 🟡 medium 🔵 low -->
<!-- category: bug perf refactor feature security debt docs -->

## Summary

The codebase is in good shape overall — recent commits have resolved prior TODO markers and tightened security. Four items remain: one critical Python bug introduced by a refactor (Splitter.py call-site/signature mismatch causing `TypeError` at runtime), one high-severity Bash standards debt (packages.sh predates the current template), one low-severity incomplete docs section (RaspberryPi README), and one medium-complexity tracked feature (Android BACKLOG).

## Task Index (topological order)

| # | ID | Title | Sev | Cat | Size | Blocks |
|---|-----|-------|-----|-----|------|--------|
| 1 | T001 | Fix `move_file_to_group` arity mismatch in Splitter.py | 🔴 | bug | S | — |
| 2 | T002 | Bring packages.sh up to project Bash standards | 🟠 | debt | L | — |
| 3 | T003 | Resolve "Settings todo" placeholder in RaspberryPi README | 🔵 | docs | S | — |
| 4 | T004 | Implement Android charwasp/modify fork with GraphicsMagick | 🟡 | feature | XL | — |

---

## Tasks

### T001 · Fix `move_file_to_group` arity mismatch in Splitter.py
**File:** `Cachyos/Scripts/WIP/gphotos/Splitter.py:88`
**Severity:** critical · **Category:** bug · **Size:** S
**Blocks:** — **Blocked by:** —

**Context:**
> Call-site at line 88 passes 4 args and assigns the return value as the new size:
> `current_group_size = move_file_to_group(file_path, current_group_folder, file_size, current_group_size)`
> Definition at line 95 only accepts 2 params and returns `bool`, not `int`:
> `def move_file_to_group(file_path, current_group_folder): ... return False`

**Intent:** After refactor commit #239 (`group_photos` complexity reduction), the call-site still passes `file_size` and `current_group_size` as positional args and uses the bool return value as the new group size. This raises `TypeError: move_file_to_group() takes 2 positional arguments but 4 were given` on the first file processed.

**Acceptance criteria:**
- [ ] `process_file()` does not raise `TypeError` when processing a directory with at least one file smaller than `target_folder_size`.
- [ ] `current_group_size` is updated correctly (incremented by `file_size`) after a successful move.
- [ ] `move_file_to_group` signature and call-site are consistent — no argument count mismatch.
- [ ] `test_splitter.py` exercises the `process_file` → `move_file_to_group` path on a mocked filesystem and asserts the returned size is an `int`.

**Implementation:**
Option A — restore 4-param signature returning updated size:
```python
def move_file_to_group(file_path, current_group_folder, file_size, current_group_size):
    abs_file_path = os.path.abspath(file_path)
    abs_group_folder = os.path.abspath(current_group_folder)
    if os.path.commonpath([abs_file_path, abs_group_folder]) != abs_group_folder:
        try:
            shutil.move(file_path, current_group_folder)
            print(f"Moved photo '{file_path}' to '{current_group_folder}'")
            return current_group_size + file_size
        except (shutil.Error, OSError) as e:
            print(f"Failed to move photo '{file_path}': {e}")
    return current_group_size
```
Option B — keep 2-param bool version, fix call-site in `process_file`:
```python
moved = move_file_to_group(file_path, current_group_folder)
if moved:
    current_group_size += file_size
```

---

### T002 · Bring packages.sh up to project Bash standards
**File:** `Cachyos/Scripts/packages.sh:1`
**Severity:** high · **Category:** debt · **Size:** L
**Blocks:** — **Blocked by:** —

**Context:**
> File begins with `#!/bin/bash` (not `#!/usr/bin/env bash`), has no `set -euo pipefail`, no `shopt`, no `IFS=$'\n\t'`, uses `echo -e` throughout, predictable `/tmp/filtered_packages.txt` and `/tmp/succeeded_packages` paths, unquoted `$package_list` expansion in `sudo pacman -S ... $package_list`, and `local start_time=$(date +%s)` which masks the return code. Uses `cd /tmp/paru || exit 1` without restoring cwd.

**Intent:** This script predates the current project template and was never migrated to match the Bash standards defined in CLAUDE.md.

**Acceptance criteria:**
- [ ] Shebang updated to `#!/usr/bin/env bash`.
- [ ] `set -Eeuo pipefail` + `shopt -s nullglob globstar extglob dotglob` + `IFS=$'\n\t'` present at top.
- [ ] All `echo -e` replaced with `printf`.
- [ ] Predictable `/tmp/` paths replaced with `mktemp`-generated names stored in variables.
- [ ] `$package_list` in `pacman -S ... $package_list` converted to array: `"${package_list[@]}"`.
- [ ] `local var=$(cmd)` patterns split to `local var; var=$(cmd)` to preserve return-code masking fix.
- [ ] `cd /tmp/paru` and `cd /tmp/yay` wrapped in subshells `( cd /tmp/paru && makepkg ... )` to avoid polluting caller's `$PWD`.
- [ ] `shellcheck --severity=style` reports zero warnings on the file; `shfmt -i 2 -ci -sr` produces no diff.

**Implementation:**
Apply CLAUDE.md script template: `#!/usr/bin/env bash`, `set -Eeuo pipefail`, trans-palette colors, standard `has/log/warn/err/die` helpers, `declare -A cfg`, `trap cleanup EXIT`, `mktemp` for all temp files with cleanup in `trap`. Replace all `cd` side-effects with subshell wrappers. Convert the `package_list` string-paste pattern to `mapfile -t` + array expansion.

---

### T003 · Resolve "Settings todo" placeholder in RaspberryPi README
**File:** `RaspberryPi/README.md:43`
**Severity:** low · **Category:** docs · **Size:** S
**Blocks:** — **Blocked by:** —

**Context:**
> `### Settings todo`
> Followed by a raw markdown code block containing `net.ipv4.ip_forward=1` and an unformatted nala URL — no explanation, no context.

**Intent:** Author intended to document recommended sysctl settings for Pi networking and link the nala mirror-fetch docs but left it as a raw placeholder.

**Acceptance criteria:**
- [ ] Section heading no longer contains "todo".
- [ ] `net.ipv4.ip_forward=1` explained with a one-line use case (router/VPN/container bridging).
- [ ] The nala link rendered as a proper Markdown hyperlink with a descriptive label.
- [ ] No bare URLs remain as block content in the section.

**Implementation:**
Replace the section at line 43–48 with:
```markdown
### Recommended sysctl settings

Enable IP forwarding when using the Pi as a router, VPN gateway, or container host:

```bash
# /etc/sysctl.d/99-pi.conf
net.ipv4.ip_forward=1

# Apply immediately
sudo sysctl -p
```

For fast APT mirror selection see the [nala fetch mirror docs](https://gitlab.com/volian/nala/-/blob/main/docs/nala-fetch.8.rst?ref_type=heads).
```

---

### T004 · Implement Android charwasp/modify fork with GraphicsMagick
**File:** `Cachyos/Scripts/Android/BACKLOG.md:9`
**Severity:** medium · **Category:** feature · **Size:** XL
**Blocks:** — **Blocked by:** —

**Context:**
> | Medium | Fork and optimize [charwasp/modify](https://github.com/charwasp/modify/) — merge into a single Python script and add GraphicsMagick support | Complex |

**Intent:** Consolidate the upstream multi-file Android asset-modification toolkit into a single self-contained `modify.py` in `Cachyos/Scripts/Android/` with GraphicsMagick (`gm convert`) as the primary image backend, falling back to ImageMagick `convert`.

**Acceptance criteria:**
- [ ] Output is a single `Cachyos/Scripts/Android/modify.py` with no relative imports or external file dependencies.
- [ ] `shutil.which("gm")` checked first; falls back to `shutil.which("convert")`; raises `RuntimeError` if neither found.
- [ ] All original `charwasp/modify` operations preserved: image resize/convert, manifest patching, APK repack.
- [ ] `python3 modify.py --help` exits 0 and documents all subcommands.
- [ ] At least one test covering the `gm`→`convert` fallback logic (mock `shutil.which` to return `None` for `gm`).
- [ ] `BACKLOG.md` action-item row removed or marked done once implemented.

**Implementation:**
```python
# Backend detection (top of modify.py)
import shutil, subprocess

_GM = shutil.which("gm")
_IM = shutil.which("convert")

def run_image_cmd(*args: str) -> None:
    if _GM:
        subprocess.run(["gm", "convert", *args], check=True)
    elif _IM:
        subprocess.run(["convert", *args], check=True)
    else:
        raise RuntimeError("Neither GraphicsMagick (gm) nor ImageMagick (convert) found in PATH")
```
Use `argparse` subparsers: `resize`, `patch-manifest`, `repack`. Reference the charwasp/modify source for per-operation logic.

---

_All tasks are independent — no topological blocking. T001 should be prioritized as it causes an immediate runtime crash._
