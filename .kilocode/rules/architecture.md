# Architecture Rules

## Script Autonomy

Every script is **standalone** — no shared library files, no `source ../lib.sh`.
Helper functions (`has`, `log`, `warn`, `err`, `die`, `dbg`, `pm_detect`) are inlined per-script.
Rationale: scripts are designed to be curl-piped to bash; external deps break that.

## Directory Ownership

| Directory | Contents | Who modifies |
|-----------|----------|-------------|
| `Cachyos/` | Arch/CachyOS scripts | Arch-specific changes only |
| `Cachyos/Scripts/WIP/` | Work-in-progress | Excluded from lint; no lint fixes |
| `RaspberryPi/` | Debian/Pi scripts | Pi-specific changes only |
| `RaspberryPi/dots/` | Dotfiles | Config changes only, no logic |
| `.github/workflows/` | CI pipelines | Only when CI behaviour must change |
| `docs/` | Reference docs | Documentation only |

## New File Placement

- Arch-specific → `Cachyos/`
- Pi/Debian-specific → `RaspberryPi/`
- Cross-distro helper → add to both subtrees as a standalone copy
- Never create a shared `lib/` or `common/` directory

## Protected Files (do not modify without explicit instruction)

- `pacman.conf`, `makepkg.conf`, `/etc/sysctl.d/*`
- `.zshrc`, `.gitconfig`
- `AGENTS.md` (canonical source for AI guidelines — also `CLAUDE.md` and `GEMINI.md` symlinks)

## Tool Fallback Chain (mandatory for external tools)

Every script that uses a non-POSIX tool must provide a fallback:

```
fd → fdfind → find
rg → grep -E
bat → cat
sd → sed -E
aria2c → curl → wget2 → wget
jaq → jq
rust-parallel → parallel → xargs -r -P$(nproc)
```

Detect once outside loops:
```bash
FD=$(command -v fd || command -v fdfind || true)
```

## CI Triggers

Workflows trigger on: `main`, `master`, `claude/**` branches.
Always test changes on a `claude/<slug>` branch before merging to main.

## Dependency Policy

No new runtime dependencies without documenting the fallback chain.
Prefer tools already in the Arch/CachyOS default or AUR repo (paru/yay installable).
