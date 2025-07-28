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
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $WORKDIR

# Sleep replacement in bash
sleepy() { read -rt 0.1 <> <(:) || :; }
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
