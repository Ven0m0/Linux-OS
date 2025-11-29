# Gemini Context: Linux-OS

This repository is a comprehensive collection of scripts, configurations, and resources for managing, customizing, and optimizing various Linux distributions (Arch/CachyOS, Debian/Raspberry Pi) and Android environments.

## 📂 Project Structure

- **`Cachyos/`**: Scripts tailored for Arch Linux and CachyOS.
  - Key actions: System updates (`Updates.sh`), cleaning (`Clean.sh`), mirror ranking (`Rank.sh`), and automated installation/setup.
  - Includes Rust-related tooling (`Rust/`).
- **`RaspberryPi/`**: optimization and maintenance scripts for Raspberry Pi OS and DietPi.
  - Includes `docs/` for specific software configurations (PiHole, CasaOS).
- **`Android/`**: Tools for Android devices, often utilizing ADB or running within Termux.
  - Focus on debloating (`android-toolkit.sh`) and optimization.
- **`Scripts/`**: General-purpose maintenance scripts (Debloat, media optimization).
- **`.github/`**: CI/CD workflows (`workflows/`) and agent instructions (`instructions/`).
- **`Linux-Settings/`**: Kernel parameters and submodule tracking.

## 💻 Development Standards

### Bash Scripting

All scripts must adhere to strict Bash standards to ensure reliability and safety.

- **Shebang & Safety:**
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail; shopt -s nullglob globstar; IFS=$'\n\t'
  export LC_ALL=C LANG=C HOME="/home/${SUDO_USER:-$USER}"
  ```
- **Idioms:**
  - Use `[[ ... ]]` for tests.
  - Use `printf` instead of `echo`.
  - Process lines with `while IFS= read -r line; do ...; done < <(cmd)`.
  - **Avoid:** Parsing `ls`, `eval`, backticks.
- **Linting:** Respect `.shellcheckrc`. Run `shellcheck` on changes.

### Tool Hierarchy

Prefer modern, faster replacements when available, but ensure fallbacks exist for portability.

| Task       | Primary Tool   | Fallback |
| :--------- | :------------- | :------- |
| **Find**   | `fd`           | `find`   |
| **Search** | `rg` (ripgrep) | `grep`   |
| **View**   | `bat`          | `cat`    |
| **Edit**   | `sd`           | `sed`    |
| **JSON**   | `jaq`          | `jq`     |

### Package Management

- **Arch:** `paru` -> `yay` -> `pacman`.
- **Debian:** `apt`.
- **Privilege Escalation:** `sudo-rs` -> `sudo` -> `doas`.

## 🚀 Common Workflows

### Updates

- **CachyOS:** `bash Cachyos/Updates.sh`
- **Raspberry Pi:** `bash RaspberryPi/update.sh`

### Cleaning

- **General:** `bash Scripts/Debloat.sh`
- **Cachyos:** `bash Cachyos/Clean.sh`

## 📝 Contribution Guidelines

1.  **Surgical Modification:** Prefer editing existing files over creating new ones unless necessary.
2.  **Debt-First:** Remove clutter and unused dependencies before adding new features.
3.  **Verification:** Always verify commands and flags. Do not guess.
4.  **Style:** Keep code concise, formatted (2-space indent), and commented only where logic is complex.

## 🛠️ Key Files

- `README.md`: Primary entry point with "curl | bash" installation examples.
- `CLAUDE.MD`: Detailed operational manual and style guide (reference this for strict coding rules).
- `todo.md`: Current task tracking.
