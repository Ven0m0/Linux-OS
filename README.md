# Linux-OS

> **Production-grade shell scripts for Arch Linux, CachyOS, and Raspberry Pi systems**

A curated collection of battle-tested automation scripts for system setup, optimization, maintenance, and customization. Designed for power users who value performance, reproducibility, and minimal bloat.

---

## 🎯 Target Systems

| **Primary** | **Secondary** | **Tertiary** |
|:------------|:--------------|:-------------|
| Arch Linux  | Debian        | Termux       |
| CachyOS     | Raspbian      | EndeavourOS  |
| Wayland     | Raspberry Pi OS | Gentoo     |
|             |               | Nobara       |
|             |               | SteamOS      |
|             |               | Bazzite      |

---

## 📂 Repository Structure

```
Linux-OS/
├── Cachyos/              # Arch/CachyOS system scripts
│   ├── Scripts/          # Curlable AIO installers
│   │   ├── bench.sh      # System benchmarking
│   │   └── Android/      # Android/Termux optimizers
│   ├── setup.sh          # Automated system configuration
│   ├── up.sh             # Comprehensive update orchestrator
│   ├── clean.sh          # System cleanup & privacy hardening
│   ├── Rank.sh           # Mirror ranking & keyring updates
│   ├── debloat.sh        # System debloating
│   └── rustbuild.sh      # Rust compilation helpers
├── RaspberryPi/          # Raspberry Pi specific scripts
│   ├── Scripts/          # Pi automation tooling
│   │   ├── setup.sh      # Initial Pi setup & optimization
│   │   ├── Kbuild.sh     # Kernel building automation
│   │   └── apkg.sh       # TUI package manager (fzf/skim)
│   ├── raspi-f2fs.sh     # F2FS imaging orchestrator
│   ├── update.sh         # Pi update script
│   ├── PiClean.sh        # Pi cleanup automation
│   └── dots/             # Dotfiles and configurations
├── docs/                 # Documentation
├── Shell-book.md         # Bash patterns & helpers
├── USEFUL.MD             # Curated resources & snippets
└── CLAUDE.md             # Development guidelines (AI context)
```

---

## 🚀 Quick Start

### Arch Linux / CachyOS

**System Update** (packages, flatpak, rust, python, npm, etc.)
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/up.sh | bash
```

**System Cleanup** (package cache, orphans, logs, privacy hardening)
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/clean.sh | bash
```

**Mirror Ranking** (optimize download speeds)
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Rank.sh | bash
```

### Raspberry Pi

**System Update**
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/update.sh | bash
```

**System Cleanup**
```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/PiClean.sh | bash
```

**F2FS Image Creation** (convert Raspbian/DietPi images to F2FS)
```bash
wget https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/raspi-f2fs.sh
chmod +x raspi-f2fs.sh
sudo ./raspi-f2fs.sh -i dietpi -d /dev/sdX -s
```

---

## 📜 Key Scripts

### Cachyos/

| Script | Description | Usage |
|:-------|:------------|:------|
| **up.sh** | All-in-one update orchestrator (system, flatpak, rust, python, npm, mise, etc.) | `curl -fsSL <URL> \| bash` |
| **clean.sh** | Comprehensive cleanup: pacman cache, orphans, logs, browser data, privacy hardening | `curl -fsSL <URL> \| bash` |
| **setup.sh** | Automated system configuration: repositories, sysctl tuning, service setup | `./setup.sh` |
| **Rank.sh** | Mirror ranking for optimal download speeds + keyring updates | `curl -fsSL <URL> \| bash` |
| **debloat.sh** | Remove bloatware and unnecessary services | `./debloat.sh` |
| **rustbuild.sh** | Rust compilation environment with optimized flags | `./rustbuild.sh` |

### RaspberryPi/

| Script | Description | Usage |
|:-------|:------------|:------|
| **setup.sh** | Pi optimization: APT config, modern tooling (fd, rg, bat, eza), optional Pi-hole | `./Scripts/setup.sh --help` |
| **raspi-f2fs.sh** | Flash images to SD/USB with F2FS root (better flash longevity) | `sudo ./raspi-f2fs.sh -h` |
| **update.sh** | Pi-specific update script with APT optimization | `curl -fsSL <URL> \| bash` |
| **PiClean.sh** | Pi cleanup: APT cache, logs, temp files | `curl -fsSL <URL> \| bash` |
| **Kbuild.sh** | Raspberry Pi kernel building with optimization flags | `./Scripts/Kbuild.sh` |
| **apkg.sh** | Interactive APT package manager using fzf/skim | `apkg --install` |

### Scripts/Android/

| Script | Description | Usage |
|:-------|:------------|:------|
| **android-optimize.sh** | Termux/Android system optimization | `./android-optimize.sh` |
| **optimize_apk.sh** | APK size reduction & optimization | `./optimize_apk.sh app.apk` |

---

## 🛠️ Features

### Arch/CachyOS Scripts
- **Multi-source updates**: pacman/paru/yay, flatpak, rustup, npm, pip/uv, mise, topgrade
- **Aggressive caching cleanup**: Package cache, build artifacts, logs, browser data
- **Privacy hardening**: Browser history/cache/cookies cleanup, SQLite optimization
- **Repository management**: Chaotic-AUR, ALHP (x86-64-v3), Artafinde, EndeavourOS
- **Build optimization**: Native CPU tuning, LTO, PGO-ready flags
- **Service debloating**: Remove unnecessary systemd services and packages

### Raspberry Pi Scripts
- **F2FS root filesystem**: Better performance and longevity on SD cards/USB
- **APT optimization**: Parallel downloads, compression, auto-upgrade config
- **Modern tooling**: fd, ripgrep, bat, eza, zoxide, navi, yt-dlp
- **Kernel compilation**: Optimized flags for Pi hardware
- **Interactive package management**: TUI with fzf/skim integration
- **Automated Pi-hole/PiKISS setup**: Optional external installers

---

## 📋 Requirements

### Arch/CachyOS
- **Base**: bash 5.0+, coreutils, sudo
- **Package managers**: pacman (+ optional: paru/yay for AUR)
- **Optional**: flatpak, rustup, npm, python/uv, topgrade, mise

### Raspberry Pi
- **Base**: bash 5.0+, coreutils, sudo, rsync
- **OS**: Debian-based (Raspbian, Raspberry Pi OS, DietPi)
- **For raspi-f2fs.sh**: f2fs-tools, parted, xz-utils, fzf (optional)
- **For Kbuild.sh**: build-essential, bc, flex, bison, libssl-dev

---

## 🔒 Safety Features

- **Dry-run mode**: Preview actions with `-d` / `--dry-run`
- **Error handling**: `set -euo pipefail`, ERR traps with line numbers
- **Cleanup traps**: Automatic temp file/mount cleanup on EXIT/INT/TERM
- **Device locking**: Prevents concurrent operations (raspi-f2fs.sh)
- **USB/MMC validation**: Safety checks for destructive operations
- **Pacman lock cleanup**: Automatic handling of stale locks

---

## 📖 Usage Examples

### Example 1: Setup fresh Arch system
```bash
# Clone repo
git clone https://github.com/Ven0m0/Linux-OS.git
cd Linux-OS/Cachyos

# Run setup (adds repos, configures system)
./setup.sh

# Install AUR helper if needed
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si

# Update system
./up.sh

# Optional: cleanup
./clean.sh
```

### Example 2: Flash DietPi to Raspberry Pi with F2FS
```bash
# Download script
wget https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/raspi-f2fs.sh
chmod +x raspi-f2fs.sh

# Flash DietPi to /dev/sdb with SSH enabled
sudo ./raspi-f2fs.sh -i dietpi -d /dev/sdb -s

# Or interactive mode (prompts for device)
sudo ./raspi-f2fs.sh
```

### Example 3: Raspberry Pi initial setup
```bash
# Clone repo on Pi
git clone https://github.com/Ven0m0/Linux-OS.git
cd Linux-OS/RaspberryPi/Scripts

# Run setup with minimal profile (no external installers)
./setup.sh --minimal

# Update system
cd .. && ./update.sh

# Cleanup
./PiClean.sh
```

### Example 4: One-liner updates
```bash
# Arch: Update everything
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/up.sh | bash

# Pi: Update + cleanup
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/update.sh | bash && \
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/RaspberryPi/PiClean.sh | bash
```

---

## 🧪 Development

### Code Standards
- **Strict mode**: `set -euo pipefail`, `shopt -s nullglob globstar`
- **Linting**: shellcheck (severity=style), shfmt (2-space indent)
- **Testing**: bats-core for unit tests, manual integration testing
- **Performance**: hyperfine for benchmarking critical paths
- **See**: [CLAUDE.md](CLAUDE.md) for detailed guidelines

### Helper Functions
All scripts include standardized helpers (from [Shell-book.md](Shell-book.md)):
- `has()` - Command existence check
- `log/msg/warn/err/die()` - Logging hierarchy
- `dbg()` - Debug logging (enabled via `DEBUG=1`)
- Trans flag color palette (LBLU/PNK/BWHT)

### Tool Hierarchy (with fallbacks)
| Task | Primary | Fallback Chain |
|:-----|:--------|:---------------|
| Find | `fd` | `fdfind` → `find` |
| Grep | `rg` | `grep -E` |
| View | `bat` | `cat` |
| Edit | `sd` | `sed -E` |
| Web | `aria2c` | `curl` → `wget` |
| JSON | `jaq` | `jq` |
| Parallel | `rust-parallel` | `parallel` → `xargs -P` |

---

## 🤝 Contributing

Contributions welcome! Please follow:
1. **Bash standards**: See [CLAUDE.md](CLAUDE.md) for style guide
2. **Testing**: Run `shellcheck` and test on target systems
3. **Atomic commits**: One logical change per commit
4. **Descriptive messages**: Explain "why" not "what"
5. **Documentation**: Update README and inline comments

---

## 📚 Additional Resources

- **[Shell-book.md](Shell-book.md)**: Bash patterns, helpers, idioms
- **[USEFUL.MD](USEFUL.MD)**: Curated resources and snippets
- **[RaspberryPi/README.md](RaspberryPi/README.md)**: Pi-specific documentation
- **[CLAUDE.md](CLAUDE.md)**: Development guidelines (AI assistant context)

---

## 🔗 Links

- **GitHub**: [Ven0m0/Linux-OS](https://github.com/Ven0m0/Linux-OS)
- **Issues**: [Report bugs](https://github.com/Ven0m0/Linux-OS/issues)
- **Arch Wiki**: [Arch Linux Documentation](https://wiki.archlinux.org/)
- **CachyOS**: [Official Site](https://cachyos.org/)
- **DietPi**: [Official Site](https://dietpi.com/)

---

## ⚠️ Disclaimer

These scripts perform system-level operations. **Always review scripts before running**, especially those executed with `curl | bash`. Use at your own risk. **Backup important data** before running destructive operations (raspi-f2fs.sh, debloat.sh, etc.).

---

## 📄 License

MIT License - See individual files for details. Scripts are provided as-is without warranty.

---

**Made with ❤️ for the Arch and Raspberry Pi communities**
