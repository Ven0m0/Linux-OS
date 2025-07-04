# Linux-OS  

### Updates

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash
```

### Cleaning

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash
```

### Rank mirrors & keyrings

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rank.sh | bash
```

### Automated install

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/Install.sh | bash
```

### Automated configuration

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/AutoSetup.sh | bash
```

### Bleachbit extra cleaner install

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/bleachbit.sh | bash
```

-----

### Misc

```
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rust/Strip-rust.sh | bash

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Debloat.sh | bash
```

### Script start:

```bash
#!/usr/bin/bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

# Script Path Awareness
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$HOME"

# Sleep replacement
# Sleeps for 0.1 seconds (instead of doing "timeout 0.1", doesnt spawn subshells --> therefore faster)
read -rt 0.1

```

## List of Linux operating systems

### Desktop:

[CachyOS](https://cachyos.org/)


### Gaming:

[Nobara](https://nobaraproject.org/)

[SteamOS](https://store.steampowered.com/steamos/buildyourown) | 
[Download](https://store.steampowered.com/steamos/download/?ver=steamdeck&snr=)

[Bazzite](https://bazzite.gg/)

[EndeavourOS](https://endeavouros.com/)

[Linux Mint](https://linuxmint.com/)

Other:

[DietPi](https://dietpi.com/)

[Raspberry Pi OS](https://www.raspberrypi.com/software/)
