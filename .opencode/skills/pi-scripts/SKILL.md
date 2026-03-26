---
name: pi-scripts
description: Raspberry Pi / Debian script conventions for this repo — APT fallback chain, F2FS imaging, loop device management, chroot operations, and ARM detection. Use when editing RaspberryPi/ scripts.
---

## APT Upgrade Hierarchy

```bash
if has apt-fast; then
  apt-fast -y full-upgrade
elif has nala; then
  nala upgrade -y
else
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" full-upgrade
fi
```

## Architecture Detection

```bash
is_pi(){ [[ $(uname -m) =~ ^(arm|aarch64) ]]; }
is_debian(){ has apt; }
```

## Loop Device Management (F2FS Imaging)

```bash
# Partition suffix: nvme/mmcblk/loop devices use 'p' prefix
[[ $dev == *@(nvme|mmcblk|loop)* ]] && p="${dev}p" || p="${dev}"
part1="${p}1"
part2="${p}2"

# Attach image to loop device
LOOP_DEV=$(losetup --find --show --partscan "$image")

# Wait for device nodes
for i in $(seq 1 10); do
  [[ -b "${LOOP_DEV}p1" ]] && break
  sleep 0.2
done
udevadm settle
```

## Chroot Pattern

```bash
mount --bind /dev  "$mnt/dev"
mount --bind /proc "$mnt/proc"
mount --bind /sys  "$mnt/sys"
chroot "$mnt" /bin/bash -c "$cmd"
```

## Cleanup for Loop/Mount

```bash
cleanup(){
  set +e
  mountpoint -q "${MNT_PT:-}" && umount -R "$MNT_PT" 2>/dev/null || :
  [[ -b ${LOOP_DEV:-} ]] && losetup -d "$LOOP_DEV" 2>/dev/null || :
  [[ -d ${WORKDIR:-} ]] && rm -rf "$WORKDIR" || :
}
trap 'cleanup' EXIT
```

## APT Non-Interactive

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get -y -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" install "$pkg"
```

## DietPi Detection

```bash
is_dietpi(){ [[ -f /boot/dietpi/.version || -f /DietPi/dietpi/.version ]]; }
```

## Package Manager Exclusions

- Never use `apt` (no scripting interface) — use `apt-get`
- `nala` preferred over `apt-get` on Debian 11+ for parallel downloads
- `apt-fast` preferred on Pi when available (aria2c backend)

## fstab / cmdline Updates

Always back up before modifying:
```bash
cp /etc/fstab "/etc/fstab.bak.$(date +%s)"
```
Use `sed -i` only with anchored patterns to avoid partial-line matches.
