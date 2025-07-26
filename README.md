# Linux-OS  

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
<details>

---
<details>
<summary><i>Rank mirrors & keyrings</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rank.sh | bash
```
<details>

---
<details>
<summary><i>Automated install</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/Install.sh | bash
```
<details>

---
<details>
<summary><i>Automated configuration</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/AutoSetup.sh | bash
```
<details>

---
<details>
<summary><i>Bleachbit extra cleaner install</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/bleachbit.sh | bash
```
<details>

---
<details>
<summary><i>Misc</i></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rust/Strip-rust.sh | bash

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Debloat.sh | bash
```
<details>

---
<details>
<summary><i>Script start</i></summary>

```bash
#!/usr/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

# Safer globbing
shopt -s nullglob globstar

# C for speed
export LC_ALL=C LANG=C

# C+UTF8 if emojis needed
export LC_ALL=C LANG=C.UTF-8

# Script Path Awareness
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$HOME"

# Sleep replacement
# Sleeps for 0.1 seconds (instead of doing "timeout 0.1", doesnt spawn subshells --> therefore faster)
sleepy() {
  read -rt 1 <> <(:) || :
}

```
<details>

---
<details>
<summary><i>Get external IP</i></summary>
```bash
curl -fsS ipinfo.io/ip || curl -fsS http://ipecho.net/plain
```
<details>

---

## Bash packages

- [Basher](https://www.basher.it/package)

- [bpkg](https://bpkg.sh)


## Linux operating systems

- [CachyOS](https://cachyos.org/)

- [Nobara](https://nobaraproject.org/)

- [SteamOS](https://store.steampowered.com/steamos/buildyourown) | 
[Download](https://store.steampowered.com/steamos/download/?ver=steamdeck&snr=)

- [Bazzite](https://bazzite.gg/)

- [EndeavourOS](https://endeavouros.com/)

- [Linux Mint](https://linuxmint.com/)

Other:

- [DietPi](https://dietpi.com/)

- [Raspberry Pi OS](https://www.raspberrypi.com/software/)
