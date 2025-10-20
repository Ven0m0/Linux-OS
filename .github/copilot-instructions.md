# Copilot Instructions: Linux-OS
## Repo map
- `Cachyos/` Arch-focused setup: `Scripts/` for AIO installers run via curl, `Rust/` for toolchains, `Firefox/` patch sets, top-level `.sh` wrappers for maintenance.
- `RaspberryPi/` imaging and upkeep; `raspi-f2fs.sh` orchestrates loop/partition flows, `Scripts/` hosts Pi automation tasks.
- `Linux-Settings/` holds reference configs (compiler, kernel, shell) consumed by scripts; treat as data sources.
- Root docs (`Shell-book.md`, `Tweaks.txt`, `todo.md`) capture house style and pending work—reuse helpers from there before inventing new ones.
## Bash defaults
- Start scripts with the standard bash shebang using /usr/bin/env bash, enable `set -euo pipefail`, set `IFS=$'\n\t'`, optionally `shopt -s nullglob globstar`, and export `LC_ALL=C LANG=C`.
- Keep 2-space indentation; use arrays + `mapfile` to avoid extra processes; inline helpers (`has`, `sleepy`, `bname`, `dname`) or lift from `Shell-book.md`.
- Ship scripts as single files callable via `curl -fsSL ... | bash`; avoid repo-relative assumptions and guard optional dependencies.
- Detect privilege + pkg managers upfront (`sudo -v`, prefer `paru`→`yay`→`pacman`; Debian flows fall back to `apt`/`dpkg`), and back destructive actions with prompts or dry-run toggles.
## Data & distro handling
- Arch routines export tuned `CFLAGS/CXXFLAGS`, `RUSTFLAGS`, and `MAKEFLAGS`, prefer LLVM tools, and gate `ld.lld` use when present.
- Raspberry Pi imaging relies on `losetup`, `parted`, `mkfs`, `rsync`, and edits `cmdline.txt`/`fstab`; preserve dry-run paths, traps, and cleanup ordering.
- Package/app installers track state first (`pacman -Q`, `flatpak list`, `cargo install --list`) and operate on missing entries—keep arrays idempotent.
- Network fetches default to hardened `curl -fsSL` invocations (proto/tls flags, background jobs). Maintain timeouts and re-use `.curl-hsts`/temp-file patterns.
## Tooling workflow
- Format with `shfmt -i 2 -ci -sr`; lint using `shellcheck` (see disabled codes in `.shellcheckrc`); run the `Harden Script` task for `shellharden` transforms.
- Prefer `fd`, `rg`, `bat`, `sd`, `zoxide` when available but always supply `find`, `grep`, `sed`, `awk`, `less` fallbacks + install hints (Arch `pacman -S --needed`, Debian `sudo apt-get install -y`).
- Use `mktemp -p "${TMPDIR:-/tmp}"`, write files atomically, trap `INT/TERM` to unmount/cleanup loop devices or temp dirs.
- Update README snippets alongside script entrypoints so the documented `curl` commands stay accurate.
