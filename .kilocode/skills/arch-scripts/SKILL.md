---
name: arch-scripts
description: Arch Linux / CachyOS script conventions for this repo — AUR helper fallback chain, package operations, systemd interaction, mirror ranking, and Rust build flags. Use when editing Cachyos/ scripts.
---

## Package Manager Hierarchy

```bash
pm_detect(){
  if has paru; then printf 'paru'; return; fi
  if has yay; then printf 'yay'; return; fi
  if has pacman; then printf 'pacman'; return; fi
  printf ''
}
PKG_MGR=${PKG_MGR:-$(pm_detect)}
```

## AUR Install Flags

```bash
$PKG_MGR -S --needed --noconfirm --removemake --cleanafter \
  --sudoloop --skipreview --batchinstall "$pkg"
```

## Check Before Install

```bash
pacman -Q "$pkg" &>/dev/null || $PKG_MGR -S --noconfirm "$pkg"
flatpak list --app | grep -qF "$pkg" || flatpak install -y "$pkg"
cargo install --list | grep -qF "$pkg" || cargo install "$pkg"
```

## Rust Build Environment

```bash
export CFLAGS="-march=native -mtune=native -O3 -pipe"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)" NINJAFLAGS="-j$(nproc)"
export AR=llvm-ar CC=clang CXX=clang++ NM=llvm-nm RANLIB=llvm-ranlib
export RUSTFLAGS="-Copt-level=3 -Ctarget-cpu=native -Ccodegen-units=1 -Cstrip=symbols -Clto=fat"
has ld.lld && export RUSTFLAGS="${RUSTFLAGS} -Clink-arg=-fuse-ld=lld"
```

## Wayland Detection

```bash
is_wayland(){ [[ ${XDG_SESSION_TYPE:-} == wayland || -n ${WAYLAND_DISPLAY:-} ]]; }
```

## Linting Exclusion

Scripts in `Cachyos/Scripts/WIP/` are excluded from shellcheck and shfmt — do not add lint-suppress comments to work-in-progress files; move them to WIP/ instead.
