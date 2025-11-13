# Linux-OS

A collection of scripts and resources for managing and customizing Linux distributions.

<details>
<summary><b>Arch scripts</b></summary>

Update:

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Updates.sh | bash
```

Clean:

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Clean.sh | bash
```

Maintenance AIO:

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/archmaint.sh | bash
```

Fetch:

```bash
curl -fsS4 https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Scripts/shell-tools/vnfetch.sh | bash
```

</details>
<details>
<summary><b>Rank mirrors & keyrings</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Rank.sh | bash
```

</details>
<details>
<summary><b>Automated install</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Scripts/Install.sh | bash
```

```bash
curl -sSfL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Scripts/Chaotic-aur.sh | bash
```

</details>

<details>
<summary><b>Automated configuration</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Scripts/AutoSetup.sh | bash
```

</details>
<details>
<summary><b>Bleachbit extra cleaner install</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Scripts/bleachbit.sh | bash
```

</details>
<details>
<summary><b>Miscellaneous scripts</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Rust/Strip-rust.sh | bash

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/main/Cachyos/Debloat.sh | bash
```

</details>
<details>
<summary><b>Install sytax highlighting for the nano editor</b></summary>

<https://github.com/scopatz/nanorc>

```bash
curl https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | sh
```

Lite version (no overwriting existing ones)

```bash
curl -fsSL https://raw.githubusercontent.com/scopatz/nanorc/master/install.sh | sh -s -- -l
```

</details>
<details>
<summary><b>Packages:</b></summary>

- <https://wiki.archlinux.org/title/Category:Lists_of_software>
- [Arch PKG](https://archlinux.org/packages)
- [AUR PKG](https://aur.archlinux.org)
- [Crates.io](https://crates.io)
- [FlatHub](https://flathub.org)
- [Lure.sh](https://lure.sh)
- [Basher](https://www.basher.it/package)
- [bpkg](https://bpkg.sh)
- [Nix](https://github.com/NixOS/nix) **_/_** [Home-manager](https://github.com/nix-community/home-manager) **|** [Nixpkgs](https://github.com/NixOS/nixpkgs) **|** [NUR](https://github.com/nix-community/NUR) **|**
- [x-cmd](https://www.x-cmd.com)

  <details>
  <summary><b>Install x-cmd</b></summary>

  bash:

  ```bash
  eval "$(curl https://get.x-cmd.com)"
  ```

  fish:

  ```sh
  curl https://get.x-cmd.com | sh
  chmod +x $HOME/.x-cmd.root/bin/x-cmd && ./$HOME/.x-cmd.root/bin/x-cmd fish --setup
  ```

  </details>

</details>

## Supported Linux Distributions

- [CachyOS](https://cachyos.org)
- [EndeavourOS](https://endeavouros.com)
- [Nobara](https://nobaraproject.org)
- [SteamOS](https://store.steampowered.com/steamos/buildyourown) ([Download](https://store.steampowered.com/steamos/download/?ver=steamdeck&snr=))
- [Bazzite](https://bazzite.gg)
- [Gentoo](https://www.gentoo.org)
- [Linux Mint](https://linuxmint.com/)
- [DietPi](https://dietpi.com/)
- [Raspberry Pi OS](https://www.raspberrypi.com/software)

## Useful websites

- [Wormhole file sharing](https://wormhole.app)
- [Online tools](https://tools.waytolearnx.com/en)
- [FFMPEG flag generator](https://alfg.github.io/ffmpeg-commander)

## TODO:

- https://github.com/sn99/Optimizing-linux

```bash
curl -fsSL https://christitus.com/linuxdev | bash
```
