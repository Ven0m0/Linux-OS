# DietPi F2FS Quick Start

## 1-Minute Setup

### Option A: Interactive (Easiest)
```bash
cd RaspberryPi
sudo ./f2fs-new.sh -i
```
Follow the prompts to select source and destination.

### Option B: One Command
```bash
# Download latest DietPi and flash to SD card
sudo ./RaspberryPi/f2fs-new.sh --device /dev/mmcblk0
```

### Option C: Create Image First
```bash
# Create F2FS image
sudo ./RaspberryPi/f2fs-new.sh --out ~/dietpi-f2fs.img

# Flash to SD card
sudo dd if=~/dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

## First Boot Checklist

1. ✅ Insert SD card into Raspberry Pi
2. ✅ Connect HDMI/serial console (recommended)
3. ✅ Power on
4. ✅ Verify boot: `mount | grep "on / type f2fs"`

## Common Commands

| Task | Command |
|------|---------|
| Interactive mode | `sudo ./f2fs-new.sh -i` |
| Flash to device | `sudo ./f2fs-new.sh --device /dev/mmcblk0` |
| Create image | `sudo ./f2fs-new.sh --out image.img` |
| Customize image | `sudo ./dietpi-chroot.sh image.img` |
| Use local file | `sudo ./f2fs-new.sh --src local.img.xz --device /dev/mmcblk0` |
| Custom compression | `sudo ./f2fs-new.sh --root-opts "compress_algorithm=lz4"` |

## Troubleshooting

### Boot Fails?
```bash
# Regenerate initramfs
sudo ./dietpi-chroot.sh /path/to/image.img
# Or: sudo ./dietpi-chroot.sh /dev/mmcblk0p2
```

### Need Help?
- [Complete Guide](../DIETPI_F2FS_GUIDE.md) - Full documentation
- [Examples](EXAMPLES.md) - Common use cases
- [Issues](https://github.com/yourusername/Linux-OS/issues) - Report bugs

## Features at a Glance

✅ Interactive fzf selection
✅ Auto-detects DietPi
✅ F2FS optimization (compression + garbage collection)
✅ Removes ext4-specific configs
✅ Supports Pi 3, 4, 5
✅ Direct device flashing or image creation
✅ Post-conversion verification

## Performance Benefits

| Metric | ext4 | F2FS | Improvement |
|--------|------|------|-------------|
| Random I/O | Baseline | +30-50% | Better |
| Write endurance | Baseline | +2-3x | Much better |
| Space efficiency | Baseline | +10-20% | Better (with compression) |

## Next Steps

1. Read [EXAMPLES.md](EXAMPLES.md) for advanced workflows
2. Check [DIETPI_F2FS_GUIDE.md](../DIETPI_F2FS_GUIDE.md) for troubleshooting
3. Customize with `dietpi-chroot.sh`

---

**Quick Links:**
- [DietPi Website](https://dietpi.com)
- [F2FS Docs](https://www.kernel.org/doc/html/latest/filesystems/f2fs.html)
- [GitHub Repo](https://github.com/yourusername/Linux-OS)
