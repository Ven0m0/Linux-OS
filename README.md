# Linux-OS

A collection of scripts and resources for managing and customizing Linux distributions.

<details>
<summary><b>Updates</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Updates.sh | bash
```

</details>

<details>
<summary><b>Cleaning</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Clean.sh | bash
```

</details>

<details>
<summary><b>Rank mirrors & keyrings</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rank.sh | bash
```

</details>

<details>
<summary><b>Automated install</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/Install.sh | bash
```

</details>

<details>
<summary><b>Automated configuration</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/AutoSetup.sh | bash
```

</details>

<details>
<summary><b>Bleachbit extra cleaner</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/bleachbit.sh | bash
```

</details>

<details>
<summary><b>Miscellaneous scripts</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Rust/Strip-rust.sh | bash

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Debloat.sh | bash
```

</details>

<details>
<summary><b>Script start template</b></summary>

```bash
#!/usr/bin/bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
shopt -s inherit_errexit 
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
#──────────── Foreground colors ────────────
BLK='\033[30m' # Black
RED='\033[31m' # Red
GRN='\033[32m' # Green
YLW='\033[33m' # Yellow
BLU='\033[34m' # Blue
MGN='\033[35m' # Magenta
CYN='\033[36m' # Cyan
WHT='\033[37m' # White
#──────────── Effects ────────────
DEF='\033[0m'  # Reset to default
BLD='\033[1m'  # Bold / Bright
#──────────── Bright colors ────────────
BRIGHT_RED='\033[91m'
BRIGHT_GRN='\033[92m'
BRIGHT_YLW='\033[93m'
BRIGHT_BLU='\033[94m'
BRIGHT_MGN='\033[95m'
BRIGHT_CYN='\033[96m'
BRIGHT_WHT='\033[97m'
#────────────────────────
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $WORKDIR

# Sleep replacement in bash
#sleepy() { read -rt 0.1 <> <(:) &>/dev/null || :; }
```

</details>

<details>
<summary><b>Get external IP</b></summary>

```bash
curl -fsS ipinfo.io/ip || curl -fsS http://ipecho.net/plain
```

</details>

## Bash Package Managers

* [Basher](https://www.basher.it/package)
* [bpkg](https://bpkg.sh)

## Supported Linux Distributions

* [CachyOS](https://cachyos.org)
* [EndeavourOS](https://endeavouros.com)
* [Nobara](https://nobaraproject.org)
* [SteamOS](https://store.steampowered.com/steamos/buildyourown) ([Download](https://store.steampowered.com/steamos/download/?ver=steamdeck&snr=))
* [Bazzite](https://bazzite.gg)
* [Gentoo](https://www.gentoo.org)
* [Linux Mint](https://linuxmint.com/)
* [DietPi](https://dietpi.com/)
* [Raspberry Pi OS](https://www.raspberrypi.com/software/)
