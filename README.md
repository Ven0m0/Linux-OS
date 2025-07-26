# Linux-OS

A collection of scripts and resources for managing and customizing Linux distributions.

---

<details>
<summary><i>Updates</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash
```

</details>

---

<details>
<summary><i>Cleaning</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash
```

</details>

---

<details>
<summary><i>Rank mirrors & keyrings</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rank.sh | bash
```

</details>

---

<details>
<summary><i>Automated install</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/Install.sh | bash
```

</details>

---

<details>
<summary><i>Automated configuration</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/AutoSetup.sh | bash
```

</details>

---

<details>
<summary><i>Bleachbit extra cleaner install</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/bleachbit.sh | bash
```

</details>

---

<details>
<summary><i>Misc</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rust/Strip-rust.sh | bash

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Debloat.sh | bash
```

</details>

---

<details>
<summary><i>Script start template</i></summary>

```bash
#!/usr/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

# Safer globbing
shopt -s nullglob globstar

# Use C locale for speed
export LC_ALL=C LANG=C

# Or C + UTF-8 if emojis needed
# export LC_ALL=C LANG=C.UTF-8

# Script path awareness
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change to home directory
cd "$HOME"

# Fast, low-overhead sleep function
sleepy() {
  read -rt 0.1 <> <(:) || :
}
```

</details>

---

<details>
<summary><i>Get external IP</i></summary>

```bash
curl -fsS ipinfo.io/ip || curl -fsS http://ipecho.net/plain
```

</details>

---

## Bash package managers

* [Basher](https://www.basher.it/package)
* [bpkg](https://bpkg.sh)

## Supported Linux distributions

* [CachyOS](https://cachyos.org/)
* [Nobara](https://nobaraproject.org/)
* [SteamOS](https://store.steampowered.com/steamos/buildyourown) • [Download](https://store.steampowered.com/steamos/download/?ver=steamdeck&snr=)
* [Bazzite](https://bazzite.gg/)
* [EndeavourOS](https://endeavouros.com/)
* [Linux Mint](https://linuxmint.com/)
* [DietPi](https://dietpi.com/)
* [Raspberry Pi OS](https://www.raspberrypi.com/software/)
