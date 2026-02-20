# Available Skills

> Quick reference of all automation scripts in this repository, organized by platform.

---

## Arch Linux / CachyOS

### System Update — `Cachyos/up.sh`

Updates the full system in one pass.

- pacman/paru/yay packages, AUR
- Flatpak runtimes and apps
- Rust toolchain (`rustup`)
- Node/npm global packages
- Python packages (`pip`/`uv`)
- `mise`-managed runtimes
- Firmware and bootloader (fwupdmgr, grub-mkconfig)

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/up.sh | bash
```

---

### System Cleanup — `Cachyos/clean.sh`

Reclaims disk space and hardens privacy.

- Package cache (pacman, paru, yay)
- Orphaned packages
- Journal logs (`journalctl --vacuum`)
- Browser cache/history/cookies (Firefox, Chromium)
- SQLite `VACUUM` on browser databases
- Temp files and build artifacts

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/clean.sh | bash
```

---

### System Setup — `Cachyos/setup.sh`

Bootstraps a fresh Arch/CachyOS install.

- Adds Chaotic AUR, ALHP, Artafinde, EndeavourOS repositories
- Installs packages from `pkg/pacman.txt` and `pkg/aur.txt`
- Configures sysctl, systemd services
- Sets up VS Code extensions, shell profiles
- Installs bun/uv packages from `pkg/bun.txt` / `pkg/uv.txt`

```bash
./Cachyos/setup.sh
```

---

### Debloat — `Cachyos/debloat.sh`

Removes bloatware and telemetry. Works on **Arch** and **Debian**.

- Removes `pkgstats` and other telemetry packages
- Disables unnecessary systemd services
- Disables fwupd P2P and similar background tasks

```bash
./Cachyos/debloat.sh
```

---

### Rust Build — `Cachyos/rustbuild.sh`

Compiles Rust projects with aggressive optimizations.

- PGO (Profile-Guided Optimization) support
- BOLT post-link optimization support
- `mold` linker integration
- Native CPU tuning (`-march=native -C target-cpu=native`)
- LTO and codegen-units=1

```bash
./Cachyos/rustbuild.sh [crate...]
# With PGO+BOLT: PGO=1 BOLT=1 ./Cachyos/rustbuild.sh
```

---

### AUR Repository Setup — `Cachyos/aur.sh`

Adds the Chaotic AUR to `pacman.conf`.

- Imports keyring
- Installs mirrorlist package
- Appends `[chaotic-aur]` section

```bash
./Cachyos/aur.sh
```

---

### SSH Key Generation — `Cachyos/ssh.sh`

Creates an `ed25519` SSH key for git operations.

- Reads email from `git config user.email` or `$GIT_AUTHOR_EMAIL`
- Saves key to `~/.ssh/id_git`
- Skips if key already exists

```bash
./Cachyos/ssh.sh
```

---

### System Benchmarking — `Cachyos/Scripts/bench.sh`

Runs a suite of system performance benchmarks.

- CPU, memory, disk I/O
- Parallelized via `nproc` workers
- Outputs summary table

```bash
./Cachyos/Scripts/bench.sh
```

---

### Package Installer — `Cachyos/Scripts/packages.sh`

Installs packages from a list file.

- Reads from `packages.txt` (one package per line)
- Handles pacman lock timeouts
- Logs results to `/var/log/pkg-install.log`

```bash
./Cachyos/Scripts/packages.sh
```

---

### System Repair — `Cachyos/Scripts/Fix.sh`

Fixes common Arch system issues.

- Stale pacman database locks
- Broken package states
- Mirror and keyring refresh

```bash
./Cachyos/Scripts/Fix.sh
```

---

## Raspberry Pi / Debian

### F2FS Image Flasher — `RaspberryPi/raspi-f2fs.sh`

Flashes OS images to SD cards/USB with an F2FS root partition.

- Auto-downloads DietPi if no image provided
- Partitions device (boot + root)
- Converts root to F2FS for better flash longevity
- Optionally enables SSH (`-s`)
- Supports dry-run (`-d`) and shrink (`-z`)

```bash
sudo ./RaspberryPi/raspi-f2fs.sh -i dietpi -d /dev/sdX -s
sudo ./RaspberryPi/raspi-f2fs.sh --help
```

---

### Pi System Update — `RaspberryPi/update.sh`

Updates a Raspberry Pi / Debian system.

- APT packages via `apt-fast`/`nala`/`apt-get`
- DietPi framework (`dietpi-update`)
- Pi-hole core and gravity
- Pi-Apps
- EEPROM firmware
- Optional: bleeding-edge firmware with `rpi-update` (`-u`)

```bash
./RaspberryPi/update.sh
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/update.sh | bash
```

---

### Pi System Cleanup — `RaspberryPi/PiClean.sh`

Comprehensive cleanup for Raspberry Pi / Debian.

- APT package cache and orphans
- Journal logs
- Temp files and trash
- Crash dumps
- Docker image/container prune (optional)
- DietPi artifacts

```bash
./RaspberryPi/PiClean.sh
```

---

### Pi Initial Setup — `RaspberryPi/Scripts/setup.sh`

Bootstraps and optimizes a fresh Raspberry Pi install.

- APT configuration (parallel downloads, compression)
- Installs modern tooling: `fd`, `rg`, `bat`, `eza`, `zoxide`, `navi`, `yt-dlp`
- I/O scheduler tuning
- SSH hardening (secure by default; `--insecure-ssh` to opt in to legacy settings)
- Optional Pi-hole / PiKISS setup (`--skip-external` to skip)
- Minimal profile: `--minimal`

```bash
./RaspberryPi/Scripts/setup.sh --help
./RaspberryPi/Scripts/setup.sh --minimal
```

---

### Kernel Builder — `RaspberryPi/Scripts/Kbuild.sh`

Builds and installs the Raspberry Pi kernel from source.

- Clones `raspberrypi/linux`
- Configures for target board
- Builds with optimized flags (`-march`, `-O2`, `-j$(nproc)`)
- Installs modules and reboots

```bash
./RaspberryPi/Scripts/Kbuild.sh
```

---

### TUI Package Manager — `RaspberryPi/Scripts/apkg.sh`

Interactive `fzf`/`skim` frontend for APT.

- Fuzzy search across all available packages
- Multi-select install/remove
- Cached package previews (TTL: 24 h)
- Background prefetch
- Falls back to `nala`/`apt-fast`/`apt-get`

```bash
./RaspberryPi/Scripts/apkg.sh --install
./RaspberryPi/Scripts/apkg.sh --remove
```

---

### DNS Blocklist Manager — `RaspberryPi/Scripts/blocklist.sh`

Manages DNS blocklists on Raspberry Pi / DietPi.

- Downloads and merges upstream blocklists
- Integrates with Pi-hole or local `/etc/hosts`

```bash
./RaspberryPi/Scripts/blocklist.sh
```

---

### Pi-hole Updater — `RaspberryPi/Scripts/pi_hole_updater.sh`

Robust Pi-hole and system updater.

- Updates Pi-hole core and gravity lists
- Runs full APT upgrade
- Requires root

```bash
sudo ./RaspberryPi/Scripts/pi_hole_updater.sh
```

---

### Container Setup — `RaspberryPi/Scripts/podman-docker.sh`

Installs and configures Podman (with Docker compatibility) on Raspberry Pi.

- Installs `podman`, `buildah`, `skopeo`
- Configures `docker` → `podman` shim
- Sets up rootless containers

```bash
./RaspberryPi/Scripts/podman-docker.sh
```

---

### System Minimizer — `RaspberryPi/Scripts/pi-minify.sh`

Aggressively reduces Raspberry Pi system footprint.

- Removes non-essential packages
- Disables unused services
- Frees RAM and storage

```bash
./RaspberryPi/Scripts/pi-minify.sh
```

---

### SQLite Tuner — `RaspberryPi/Scripts/sqlite-tune.sh`

Applies performance pragmas to SQLite databases.

- Modes: `safe` (default), `aggressive`, `readonly`
- Sets WAL mode, cache size, synchronous, temp store
- Safe for running databases

```bash
./RaspberryPi/Scripts/sqlite-tune.sh path/to/db.sqlite [aggressive|safe|readonly]
```

---

### Pi System Repair — `RaspberryPi/Scripts/Fix.sh`

Fixes common Debian/Raspberry Pi system issues.

- APT lock cleanup
- Broken package state repair
- Dependency resolution

```bash
./RaspberryPi/Scripts/Fix.sh
```

---

### DietPi Chroot — `RaspberryPi/dietpi-chroot.sh`

Chroots into an ARM64 DietPi/PiOS image from an x86_64 host.

- Uses QEMU user-mode emulation (`qemu-aarch64-static`)
- Mounts image, sets up bind mounts
- Used for F2FS initramfs regeneration and image customization
- Optional shrink (`-z`)

```bash
sudo ./RaspberryPi/dietpi-chroot.sh path/to/image.img
sudo ./RaspberryPi/dietpi-chroot.sh --help
```

---

## Android / Termux

### Android Optimizer — `Cachyos/Scripts/Android/android-optimize.sh`

Optimizes a Termux/Android environment.

- Installs essential Termux packages
- Configures storage, shell, and package mirrors
- Tunes Android settings for performance

```bash
./Cachyos/Scripts/Android/android-optimize.sh
```

---

### Media Optimizer — `Cachyos/Scripts/Android/media-optimizer.sh`

Bulk compresses images and videos.

- Images → WebP (with quality/size control)
- Videos → AV1 via SVT-AV1-Essential
- Parallel processing (`nproc` workers)
- Dry-run mode supported

```bash
./Cachyos/Scripts/Android/media-optimizer.sh [directory]
```

---

### Cache Cleaner — `Cachyos/Scripts/Android/cachie.sh`

Clears app caches and frees storage on Android/Termux.

- Reports low-storage threshold
- Cleans package manager caches
- Configurable minimum free storage percentage

```bash
./Cachyos/Scripts/Android/cachie.sh
```

---

## Summary Table

| Skill | Script | Platform | One-liner |
|:------|:-------|:---------|:----------|
| System update | `Cachyos/up.sh` | Arch/CachyOS | `curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/up.sh \| bash` |
| System cleanup | `Cachyos/clean.sh` | Arch/CachyOS | `curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/clean.sh \| bash` |
| Fresh install setup | `Cachyos/setup.sh` | Arch/CachyOS | `./setup.sh` |
| Debloat | `Cachyos/debloat.sh` | Arch + Debian | `./debloat.sh` |
| Rust build (PGO/BOLT) | `Cachyos/rustbuild.sh` | Arch/CachyOS | `./rustbuild.sh` |
| Chaotic AUR setup | `Cachyos/aur.sh` | Arch | `./aur.sh` |
| SSH key gen | `Cachyos/ssh.sh` | Arch/CachyOS | `./ssh.sh` |
| Benchmarking | `Cachyos/Scripts/bench.sh` | Arch | `./Scripts/bench.sh` |
| Package install | `Cachyos/Scripts/packages.sh` | Arch | `./Scripts/packages.sh` |
| System repair | `Cachyos/Scripts/Fix.sh` | Arch | `./Scripts/Fix.sh` |
| F2FS imaging | `RaspberryPi/raspi-f2fs.sh` | Pi | `sudo ./raspi-f2fs.sh -i dietpi -d /dev/sdX` |
| Pi update | `RaspberryPi/update.sh` | Pi/Debian | `curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/update.sh \| bash` |
| Pi cleanup | `RaspberryPi/PiClean.sh` | Pi/Debian | `./PiClean.sh` |
| Pi setup | `RaspberryPi/Scripts/setup.sh` | Pi/Debian | `./Scripts/setup.sh` |
| Kernel build | `RaspberryPi/Scripts/Kbuild.sh` | Pi | `./Scripts/Kbuild.sh` |
| Package TUI | `RaspberryPi/Scripts/apkg.sh` | Pi/Debian | `./Scripts/apkg.sh --install` |
| DNS blocklist | `RaspberryPi/Scripts/blocklist.sh` | Pi/Debian | `./Scripts/blocklist.sh` |
| Pi-hole update | `RaspberryPi/Scripts/pi_hole_updater.sh` | Pi/Debian | `sudo ./Scripts/pi_hole_updater.sh` |
| Container setup | `RaspberryPi/Scripts/podman-docker.sh` | Pi/Debian | `./Scripts/podman-docker.sh` |
| System minimize | `RaspberryPi/Scripts/pi-minify.sh` | Pi/Debian | `./Scripts/pi-minify.sh` |
| SQLite tuning | `RaspberryPi/Scripts/sqlite-tune.sh` | Pi/Debian | `./Scripts/sqlite-tune.sh db.sqlite` |
| Pi repair | `RaspberryPi/Scripts/Fix.sh` | Pi/Debian | `./Scripts/Fix.sh` |
| ARM64 chroot | `RaspberryPi/dietpi-chroot.sh` | x86_64 host | `sudo ./dietpi-chroot.sh image.img` |
| Android optimize | `Cachyos/Scripts/Android/android-optimize.sh` | Android/Termux | `./android-optimize.sh` |
| Media compress | `Cachyos/Scripts/Android/media-optimizer.sh` | Android/Termux | `./media-optimizer.sh [dir]` |
| Cache clean | `Cachyos/Scripts/Android/cachie.sh` | Android/Termux | `./cachie.sh` |
