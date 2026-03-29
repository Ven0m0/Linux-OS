---
description: Check-only lint pass (no writes) — exits non-zero if any violations found
agent: code
---

Run lint in check-only mode. No files are modified. Exit non-zero on any violation.

```bash
./lint-format.sh -c
```

If `lint-format.sh` is missing:
```bash
fd -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs shellcheck --severity=error
fd -t f -e sh . | grep -v 'Cachyos/Scripts/WIP' | xargs shfmt -i 2 -ci -sr -l
```

Output: list of files with violations, zero output = clean.
