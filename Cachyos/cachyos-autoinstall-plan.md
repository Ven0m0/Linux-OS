# CachyOS Auto-Installer — Strategic Plan

## Executive Summary

A single bash script (`cachyos-autoinstall.sh`) hosted on GitHub, executed via `curl -fsSL https://raw.githubusercontent.com/Ven0m0/repo/main/cachyos-autoinstall.sh | bash` from the CachyOS live USB. The script reads a user-editable config block at the top, generates a valid `settings.json`, and invokes the bundled `cachyos-installer` binary in headless mode. A post-install hook system handles everything the GUI can't (dotfiles, extra packages, services, AUR helpers).

Two deployment strategies are planned: **Strategy A** (recommended) wraps the existing CLI installer's headless mode; **Strategy B** (fallback) does a raw pacstrap-based install with CachyOS repos for full manual control if the CLI installer binary is absent or broken.

---

## Architecture Decision: Wrapper vs Raw Install

| Criterion | A: CLI Installer Wrapper | B: Raw Pacstrap |
|---|---|---|
| Complexity | Low — generate JSON, run binary | High — replicate installer logic |
| Maintenance | Low — tracks upstream installer | High — must track pacman/repo changes |
| Partition handling | Handled by installer | Must implement sgdisk/mkfs/mount |
| Package selection | Installer knows DE metapackages | Must maintain package lists per DE |
| CachyOS repo setup | Handled by installer | Must run `cachyos-repo.sh` manually |
| Kernel selection | Handled by installer | Must install + mkinitcpio manually |
| Bootloader | Handled by installer | Must configure systemd-boot/grub |
| Failure risk | Installer tested upstream | Any pacstrap step can diverge |
| Availability | Always on CachyOS live USB | Works on any Arch live USB too |

**Decision: Strategy A primary, Strategy B as opt-in fallback flag (`--raw`).**

---

## Task Breakdown

### Phase 0: Script Skeleton & Config Schema (S)

**T0.1** — Define config block format at script top. All values the GUI exposes must be configurable here. Schema:

```bash
# ══════════════════════════════════════════════════════════════
# CONFIGURATION — Edit these values before running
# ══════════════════════════════════════════════════════════════

# Target device (auto-detect if empty — picks largest non-USB disk)
DEVICE=""

# Partitioning
FILESYSTEM="btrfs"                    # btrfs | ext4 | xfs | f2fs | zfs
BOOT_SIZE="4G"                        # EFI system partition size
SWAP_SIZE="0"                         # 0 = no swap partition, "auto" = match RAM
BTRFS_SUBVOLUMES="default"            # "default" | "custom" (define CUSTOM_SUBVOLS below)
CUSTOM_SUBVOLS=()                     # ("/@snapshots:/.snapshots" "/@docker:/var/lib/docker")
MOUNT_OPTS=""                         # e.g. "compress=zstd:3,noatime" (empty = installer defaults)
LUKS_ENCRYPT=false                    # true = LUKS2 encryption on root
LUKS_PASSWORD=""                      # required if LUKS_ENCRYPT=true

# System
HOSTNAME="cachyos"
LOCALE="de_DE"                        # language locale
XKBMAP="de"                           # keyboard layout
TIMEZONE="Europe/Berlin"              # timedatectl list-timezones

# User
USER_NAME=""                          # required
USER_PASS=""                          # required (plaintext — script runs locally)
USER_SHELL="/bin/bash"                # /bin/bash | /bin/zsh | /bin/fish
ROOT_PASS=""                          # empty = locked root (sudo only)
USER_GROUPS="wheel,video,audio,input" # additional groups

# Desktop / Server
DESKTOP="kde"                         # kde | gnome | xfce | sway | wayfire | hyprland |
                                      # i3wm | openbox | bspwm | lxqt | cutefish |
                                      # budgie | cinnamon | ukui | mate | qtile | ""
SERVER_MODE=false                     # true = skip DE, minimal server install

# Kernel
KERNEL="linux-cachyos"                # linux-cachyos | linux-cachyos-bore | linux-cachyos-bmq |
                                      # linux-cachyos-cfs | linux-cachyos-pds | linux-cachyos-lts |
                                      # linux-zen | space-separated for multiple

# Bootloader
BOOTLOADER="systemd-boot"            # systemd-boot | grub | refind | limine

# Post-install
POST_INSTALL_SCRIPT=""               # URL or local path to post-install script
EXTRA_PACKAGES=()                    # ("firefox" "neovim" "git" "base-devel")
ENABLE_SERVICES=()                   # ("bluetooth" "NetworkManager" "sshd")
AUR_HELPER=""                        # "paru" | "yay" | "" (none)
DOTFILES_REPO=""                     # git clone URL for dotfiles
DOTFILES_SCRIPT=""                   # script to run inside dotfiles dir (e.g. "install.sh")

# Behavior
DRY_RUN=false                        # true = generate settings.json but don't install
CONFIRM_BEFORE_INSTALL=true          # false = fully unattended, no confirmation prompt
LOG_FILE="/tmp/cachyos-autoinstall.log"
COLOR_OUTPUT=true
```

**Acceptance:** Config block is valid bash, all variables have sane defaults, `shellcheck` clean.

**T0.2** — Script header: shebang, `set -euo pipefail`, color helpers, logging to `$LOG_FILE` via `tee`, trap for cleanup on failure.

**T0.3** — Argument parsing: `--dry-run`, `--yes` (skip confirm), `--config <url>` (fetch remote config file to override inline defaults), `--raw` (Strategy B), `--help`.

---

### Phase 1: Preflight Validation (M)

**T1.1** — Environment checks:
- Running as root (or auto-elevate with sudo)
- Running from live USB (check `/run/archiso` or `lsblk` for ISO9660)
- Internet connectivity (`ping -c1 -W3 cachyos.org`)
- `cachyos-installer` binary exists in PATH (Strategy A gate — fall back to B if missing and `--raw` not given)
- UEFI vs BIOS detection (`[ -d /sys/firmware/efi ]`) — restrict bootloader choices accordingly

**T1.2** — Config validation function `validate_config()`:
- `DEVICE` exists as block device or auto-detect succeeds
- `FILESYSTEM` is in allowed set
- `BOOTLOADER` compatible with firmware type (systemd-boot/refind/limine require UEFI)
- `USER_NAME` and `USER_PASS` are non-empty
- `LUKS_ENCRYPT=true` requires non-empty `LUKS_PASSWORD`
- `DESKTOP` is in known set or empty
- `KERNEL` entries are valid package names
- `POST_INSTALL_SCRIPT` URL is reachable if set
- All partition sizes parseable

**T1.3** — Device auto-detection when `DEVICE=""`:
- `lsblk -dnpo NAME,SIZE,TYPE,TRAN` → filter `type=disk`, exclude `tran=usb`
- Pick largest remaining disk
- Print detected device, require confirmation unless `--yes`

**T1.4** — Disk safety gate:
- Show current partition table of target device
- Warn if device has existing partitions / filesystems
- Require explicit confirmation (bypass with `--yes`)
- **Never** touch a mounted device

---

### Phase 2: settings.json Generation (M)

**T2.1** — Partition plan builder function `build_partitions()`:
- UEFI: create boot partition entry (`/boot`, `$BOOT_SIZE`, `vfat`, `type: "boot"`)
- Optional swap partition if `SWAP_SIZE != "0"` (calculate from `free -b` if `"auto"`)
- Root partition: remaining space, `$FILESYSTEM`, `type: "root"`
- Partition naming: derive from `$DEVICE` (e.g., `/dev/nvme0n1` → `/dev/nvme0n1p1`, `/dev/sda` → `/dev/sda1`)
- BIOS: no EFI partition, add `bios_boot` 1M partition for grub

**T2.2** — Subvolume resolution:
- `"default"` → standard CachyOS btrfs layout: `/@`, `/@home`, `/@root`, `/@srv`, `/@cache`, `/@tmp`, `/@log`
- `"custom"` → parse `CUSTOM_SUBVOLS` array into JSON array of `{"subvolume": "/@x", "mountpoint": "/x"}` objects
- Only applies when `FILESYSTEM="btrfs"`

**T2.3** — JSON assembly function `generate_settings_json()`:
- Use heredoc with variable interpolation (no jq dependency needed for generation, but validate with `python3 -m json.tool` or `jq -e .` if available)
- Map all config vars to the settings.json schema:

```
menus            → 1 (Simple Install)
headless_mode    → true
device           → $DEVICE
fs_name          → $FILESYSTEM
partitions       → from build_partitions()
subvolumes       → from subvolume resolution
mount_opts       → $MOUNT_OPTS (if set)
hostname         → $HOSTNAME
locale           → $LOCALE
xkbmap           → $XKBMAP
timezone          → $TIMEZONE
user_name        → $USER_NAME
user_pass        → $USER_PASS
user_shell       → $USER_SHELL
root_pass        → $ROOT_PASS
kernel           → $KERNEL
desktop          → $DESKTOP
bootloader       → $BOOTLOADER
server_mode      → $SERVER_MODE
post_install     → (generated wrapper script path, see Phase 3)
```

**T2.4** — Write `settings.json` to `/root/settings.json` (installer working directory). If `DRY_RUN=true`, print JSON to stdout and exit.

**T2.5** — JSON validation: parse with `python3 -c "import json,sys; json.load(sys.stdin)"` or `jq -e . >/dev/null`.

---

### Phase 3: Post-Install Hook System (L)

The CLI installer's `post_install` field points to a single script. We generate a wrapper that chains all post-install tasks.

**T3.1** — Generate `/tmp/cachyos-post-install.sh` dynamically from config:

```
#!/bin/bash
set -euo pipefail

CHROOT="/mnt"  # installer mounts target here

# --- Extra packages ---
if [ ${#EXTRA_PACKAGES[@]} -gt 0 ]; then
    arch-chroot "$CHROOT" pacman -S --noconfirm "${EXTRA_PACKAGES[@]}"
fi

# --- AUR helper ---
if [ -n "$AUR_HELPER" ]; then
    # Install base-devel if not present, clone + makepkg as $USER_NAME
    arch-chroot "$CHROOT" su - "$USER_NAME" -c "
        git clone https://aur.archlinux.org/${AUR_HELPER}-bin.git /tmp/${AUR_HELPER}
        cd /tmp/${AUR_HELPER} && makepkg -si --noconfirm
    "
fi

# --- Enable services ---
for svc in "${ENABLE_SERVICES[@]}"; do
    arch-chroot "$CHROOT" systemctl enable "$svc"
done

# --- User groups ---
arch-chroot "$CHROOT" usermod -aG "$USER_GROUPS" "$USER_NAME"

# --- Dotfiles ---
if [ -n "$DOTFILES_REPO" ]; then
    arch-chroot "$CHROOT" su - "$USER_NAME" -c "
        git clone '$DOTFILES_REPO' ~/dotfiles
        ${DOTFILES_SCRIPT:+cd ~/dotfiles && bash '$DOTFILES_SCRIPT'}
    "
fi

# --- Custom post-install script ---
if [ -n "$POST_INSTALL_SCRIPT" ]; then
    if [[ "$POST_INSTALL_SCRIPT" == http* ]]; then
        curl -fsSL "$POST_INSTALL_SCRIPT" | arch-chroot "$CHROOT" bash
    else
        arch-chroot "$CHROOT" bash "$POST_INSTALL_SCRIPT"
    fi
fi
```

**T3.2** — Make the wrapper executable, set `post_install` field in settings.json to its path.

**T3.3** — Ensure `arch-chroot` is available in live env (it is — `arch-install-scripts` is on the ISO).

---

### Phase 4: Installer Execution (S)

**T4.1** — Pre-install summary: print formatted table of all choices (device, FS, DE, kernel, bootloader, packages, etc.). Color-coded.

**T4.2** — Confirmation gate (unless `--yes`): "This will ERASE $DEVICE. Continue? [y/N]"

**T4.3** — Strategy A execution:
```bash
cd /root
# settings.json is already here from Phase 2
cachyos-installer 2>&1 | tee -a "$LOG_FILE"
exit_code=${PIPESTATUS[0]}
```

**T4.4** — Strategy B execution (if `--raw` or installer missing):
- `sgdisk --zap-all "$DEVICE"`
- Create partitions via `sgdisk`
- `mkfs.*` per partition
- Mount to `/mnt` with subvolumes if btrfs
- `pacstrap /mnt base linux-cachyos cachyos-settings ...`
- `genfstab -U /mnt >> /mnt/etc/fstab`
- `arch-chroot` for locale, timezone, hostname, user, bootloader, mkinitcpio
- Add CachyOS repos via `cachyos-repo.sh` or manual mirrorlist
- Run post-install hooks

**T4.5** — Exit code handling: on failure, dump last 50 lines of log, suggest `paste-cachyos` for bug reports.

---

### Phase 5: LUKS Encryption Support (M)

**T5.1** — When `LUKS_ENCRYPT=true`:
- Create LUKS2 container on root partition before filesystem creation
- Open container: `cryptsetup luksFormat --type luks2 /dev/XXXpN <<< "$LUKS_PASSWORD"`
- Open: `cryptsetup open /dev/XXXpN cryptroot`
- Modify partition entries in settings.json to use `/dev/mapper/cryptroot`
- **Note:** The CLI installer's headless mode may not natively support LUKS. If not, LUKS is Strategy B-only or requires pre-formatting before invoking the installer.

**T5.2** — Validate that `LUKS_ENCRYPT=true` forces Strategy B if CLI installer lacks LUKS headless support.

**T5.3** — Post-install: ensure `encrypt` hook in `/etc/mkinitcpio.conf` HOOKS, regenerate initramfs, configure bootloader with `cryptdevice=` parameter.

---

### Phase 6: Remote Config Support (S)

**T6.1** — `--config <url>` flag: fetch a remote bash file that overrides config variables.
```bash
if [ -n "$CONFIG_URL" ]; then
    source <(curl -fsSL "$CONFIG_URL")
fi
```

**T6.2** — Config file format: identical to the config block at the script top. Users maintain per-machine configs in their repo (e.g., `configs/desktop.conf`, `configs/server.conf`).

**T6.3** — Allow `--config` to also be a local file path for USB-based configs.

---

### Phase 7: Testing & Validation (L)

**T7.1** — VM test matrix (QEMU/libvirt):

| Test Case | UEFI | BIOS | FS | DE | Bootloader | LUKS |
|---|---|---|---|---|---|---|
| Minimal desktop | ✓ | | btrfs | kde | systemd-boot | no |
| Server headless | ✓ | | ext4 | (none) | systemd-boot | no |
| Full custom | ✓ | | btrfs | hyprland | grub | yes |
| BIOS legacy | | ✓ | ext4 | xfce | grub | no |
| Dry run | ✓ | | btrfs | kde | systemd-boot | no |
| Multi-kernel | ✓ | | xfs | gnome | refind | no |

**T7.2** — Automated smoke test: `--dry-run` mode validates JSON output against a JSON schema.

**T7.3** — Shellcheck + shfmt enforcement in CI.

**T7.4** — Test `--config <url>` with GitHub raw URLs.

---

### Phase 8: Documentation & Repo Setup (S)

**T8.1** — README.md: one-liner usage, config reference table, examples for common setups (gaming desktop, dev workstation, headless server).

**T8.2** — Example config files in `configs/` directory.

**T8.3** — GitHub Actions: shellcheck, shfmt, dry-run test on push.

---

## Dependency Graph (Critical Path)

```
T0.1 (config schema)
  ├→ T0.2 (skeleton) → T0.3 (args)
  ├→ T1.2 (validation) → T1.1 (env checks) → T1.3 (auto-detect) → T1.4 (safety)
  ├→ T2.1 (partitions) → T2.2 (subvols) → T2.3 (JSON assembly) → T2.4 (write) → T2.5 (validate)
  ├→ T3.1 (post-install gen) → T3.2 (wire up)
  └→ T4.1 (summary) → T4.2 (confirm) → T4.3 (execute A) / T4.4 (execute B)

T5.* (LUKS) branches from T2.1, feeds into T4.4
T6.* (remote config) branches from T0.3
T7.* (testing) depends on all above
T8.* (docs) parallel with T7.*
```

**Critical path:** T0.1 → T2.3 → T3.1 → T4.3 — the fastest path to a working installer is: config schema → JSON generation → post-install hooks → execute.

---

## Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | CLI installer headless mode has undocumented field requirements or breaks on edge cases | Install fails | Medium | Strategy B fallback; test all field combos in VM |
| R2 | CLI installer doesn't support LUKS in headless mode | LUKS users blocked | High | Force Strategy B for LUKS; document clearly |
| R3 | Partition naming logic wrong for unusual devices (mmcblk, nvme vs sda) | Wrong partitions written | Medium | Comprehensive device name → partition name mapping function; test with multiple device types |
| R4 | CachyOS updates installer JSON schema | Script generates invalid JSON | Low | Pin to known-good schema; monitor upstream releases |
| R5 | `curl \| bash` executed without reviewing config → data loss | User loses data | Medium | Default `CONFIRM_BEFORE_INSTALL=true`; big red warning in README |
| R6 | Post-install chroot environment missing expected binaries | Post-install hooks fail | Low | Check for each binary before use; skip gracefully with warning |
| R7 | btrfs subvolume naming diverges from CachyOS default layout | Broken snapper/timeshift | Medium | Pull default subvol list from installer source; keep in sync |
| R8 | ZFS support requires DKMS + headers during install | ZFS install may fail | Medium | Ensure `linux-cachyos-headers` is pulled alongside kernel for ZFS |

---

## Effort Estimates

| Phase | Size | Estimate | Notes |
|---|---|---|---|
| P0: Skeleton + Config | S | 2-3 hrs | Mostly boilerplate |
| P1: Preflight | M | 3-4 hrs | Device detection logic needs care |
| P2: JSON Generation | M | 3-4 hrs | Partition plan builder is the hard part |
| P3: Post-Install Hooks | L | 4-6 hrs | AUR helper + dotfiles + chroot edge cases |
| P4: Installer Execution | S | 2-3 hrs | Strategy A simple; B is the fallback |
| P5: LUKS | M | 3-4 hrs | Strategy B only likely; initramfs config |
| P6: Remote Config | S | 1 hr | Simple source + curl |
| P7: Testing | L | 6-8 hrs | VM matrix across all combos |
| P8: Docs | S | 1-2 hrs | README + examples |
| **Total** | | **~25-35 hrs** | |

---

## Implementation Order (Recommended)

1. **P0** — Get the script skeleton running with config block
2. **P2** — JSON generation (core value — can `--dry-run` test immediately)
3. **P1** — Preflight validation (catches errors before destructive ops)
4. **P4.3** — Strategy A execution (first working end-to-end in VM)
5. **P3** — Post-install hooks (the "like the GUI but better" differentiator)
6. **P6** — Remote config (enables multi-machine workflows)
7. **P5** — LUKS support (Strategy B path)
8. **P4.4** — Strategy B raw install (fallback completeness)
9. **P7** — Full test matrix
10. **P8** — Docs + CI

**MVP (phases 0+2+1+4.3):** ~10-14 hrs → working headless CachyOS install from curl pipe.

---

## File Structure in Repo

```
cachyos-autoinstall/
├── cachyos-autoinstall.sh          # Main script (curl target)
├── configs/
│   ├── desktop-kde.conf            # Example: KDE gaming desktop
│   ├── desktop-hyprland.conf       # Example: Hyprland rice
│   ├── server-minimal.conf         # Example: headless server
│   └── dev-workstation.conf        # Example: dev setup with dotfiles
├── post-install/
│   ├── gaming.sh                   # Steam, Proton, gamemode, mangohud
│   ├── dev-tools.sh                # neovim, tmux, rust, node, python
│   └── dotfiles-deploy.sh          # Generic dotfiles deployment
├── .github/
│   └── workflows/
│       └── lint.yml                # shellcheck + shfmt + dry-run
├── README.md
└── LICENSE
```

---

## Usage Examples

**Minimal (interactive device selection):**
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/cachyos-autoinstall/main/cachyos-autoinstall.sh | bash
```

**Fully unattended with remote config:**
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/cachyos-autoinstall/main/cachyos-autoinstall.sh | bash -s -- --config https://raw.githubusercontent.com/Ven0m0/cachyos-autoinstall/main/configs/desktop-kde.conf --yes
```

**Dry run (validate config, print JSON, no install):**
```bash
curl -fsSL ... | bash -s -- --config ... --dry-run
```

**Local config from USB:**
```bash
curl -fsSL ... | bash -s -- --config /run/media/liveuser/USB/my-config.conf --yes
```
