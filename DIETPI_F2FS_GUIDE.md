# DietPi F2FS Conversion Guide

## Overview

This guide explains how to convert DietPi (which uses ext4 by default) to F2FS for improved SD card performance and longevity.

## Prerequisites

- Raspberry Pi 3, 4, or 5
- Kernel with F2FS support (most modern kernels have this)
- Root access (`sudo`)
- Required tools: `mkfs.f2fs`, `losetup`, `rsync`, `parted`, `qemu-aarch64-static`

## Workflow

### Method 1: Interactive Mode (Easiest)

Use fzf-based interactive selection for source and destination:

```bash
# Launch interactive mode
sudo ./RaspberryPi/f2fs-new.sh -i

# You'll be prompted to:
# 1. Select source:
#    - Download DietPi Trixie (latest)
#    - Use local image file (with file browser)
#    - Enter custom URL
#
# 2. Select output:
#    - Create image file (specify path)
#    - Flash to device (with device browser)

# The script handles everything automatically
```

### Method 2: Create F2FS Image

Convert a DietPi image file from ext4 to F2FS:

```bash
# Download and convert DietPi image to F2FS
sudo ./RaspberryPi/f2fs-new.sh --out ~/dietpi-f2fs.img

# Use local image file
sudo ./RaspberryPi/f2fs-new.sh --src ~/DietPi.img.xz --out ~/dietpi-f2fs.img

# The script will:
# 1. Download/prepare source image
# 2. Convert root partition from ext4 to F2FS
# 3. Remove ext4-specific configs
# 4. Update fstab and cmdline.txt
# 5. Prepare initramfs for F2FS
# 6. Save output image

# Optional: Regenerate initramfs (recommended for first boot)
sudo ./RaspberryPi/dietpi-chroot.sh ~/dietpi-f2fs.img
# Inside chroot, the script auto-runs: update-initramfs -u
# Type 'exit' when done

# Flash to SD card
sudo dd if=~/dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

### Method 3: Flash Directly to Device

Skip image creation and flash directly to SD card:

```bash
# Interactive device selection
sudo ./RaspberryPi/f2fs-new.sh -i
# Choose "Flash to device" option

# Or specify device directly
sudo ./RaspberryPi/f2fs-new.sh --src ~/DietPi.img.xz --device /dev/mmcblk0

# Download and flash in one step
sudo ./RaspberryPi/f2fs-new.sh --device /dev/mmcblk0
```

### Method 4: Advanced - Using raspi-f2fs.sh

For advanced users who want more control over the flashing process:

```bash
# Interactive mode with fzf selection
sudo ./RaspberryPi/raspi-f2fs.sh

# Flash DietPi image to SD card with F2FS
sudo ./RaspberryPi/raspi-f2fs.sh -i dietpi -d /dev/mmcblk0

# Use local image file with interactive device selection
sudo ./RaspberryPi/raspi-f2fs.sh -i ~/DietPi.img.xz

# Enable SSH on first boot
sudo ./RaspberryPi/raspi-f2fs.sh -i dietpi -d /dev/mmcblk0 -s

# The script will:
# 1. Download/prepare source image
# 2. Detect DietPi installation
# 3. Verify F2FS kernel support
# 4. Backup critical configs
# 5. Create F2FS partitions on target
# 6. Clone data from source
# 7. Remove ext4-specific configs
# 8. Update boot configuration
# 9. Verify conversion
```

## Features

### DietPi Detection
- Automatically detects DietPi installations
- Identifies Pi model (3/4/5) and DietPi version
- Applies DietPi-specific optimizations

### Config Management
- **Backed up:** `/boot/dietpi/.installed`, `dietpi.txt`, network configs, hostname
- **Removed:** ext4 journal settings, ext4-specific cron jobs/systemd timers
- **Updated:** fstab with F2FS mount options, cmdline.txt with rootfstype=f2fs

### F2FS Optimization
- Compression enabled: `compress_algorithm=zstd`
- Advanced features: `compress_chksum,atgc,gc_merge`
- Optimal mount options for SD card longevity

### Safety Features
- Pre-conversion verification of F2FS kernel support
- Post-conversion verification (fstab, cmdline, mountability)
- Detailed summary with warnings and next steps
- Backup of critical configs (in `/tmp/dietpi_backup` during conversion)

## Post-Conversion Steps

1. **First Boot:**
   - Have HDMI/serial console ready
   - Watch for boot messages
   - If kernel panic occurs, check F2FS module availability

2. **Verify F2FS:**
   ```bash
   # Check root filesystem type
   mount | grep "on / "
   # Should show: type f2fs

   # Check fstab
   cat /etc/fstab
   # Should show: / f2fs defaults,noatime,compress_algorithm=zstd...

   # Check kernel module
   lsmod | grep f2fs
   # Should show f2fs module loaded
   ```

3. **Optional: Regenerate Initramfs (if boot issues occur):**
   ```bash
   # On the Pi (if it boots)
   sudo update-initramfs -u

   # Or from another machine using chroot
   sudo ./RaspberryPi/dietpi-chroot.sh /path/to/sdcard/image.img
   ```

## Troubleshooting

### Boot Fails with Kernel Panic
- **Cause:** Kernel missing F2FS support
- **Fix:** Use a kernel with CONFIG_F2FS_FS=y or CONFIG_F2FS_FS=m

### Root Partition Won't Mount
- **Cause:** Missing f2fs module in initramfs
- **Fix:** Run `dietpi-chroot.sh` on the image and regenerate initramfs

### Compression Not Working
- **Cause:** Kernel older than 5.6 or missing CONFIG_F2FS_FS_COMPRESSION=y
- **Fix:** Upgrade kernel or remove compression options from fstab mount options

### Performance Issues
- **Check:** Verify compression is enabled: `cat /proc/fs/f2fs/*/compress_extension`
- **Tune:** Adjust mount options in `/etc/fstab`

## Script Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `raspi-f2fs.sh` | Flash images to devices with F2FS | Device-to-device conversion |
| `f2fs-new.sh` | Create F2FS images from ext4 | Image creation/conversion |
| `dietpi-chroot.sh` | Chroot into Pi images | Post-conversion tasks, initramfs regen |

## Advanced Options

### Custom F2FS Options
Edit `f2fs-new.sh` and modify the `ROOT_OPTS` variable:
```bash
ROOT_OPTS="compress_algorithm=lz4,compress_chksum,atgc"  # Use LZ4 instead of zstd
```

### Custom Image Source
Both scripts support:
- URLs: `https://example.com/image.img.xz`
- Local files: `/path/to/image.img` or `image.img.xz`
- Shortcut: `dietpi` (downloads latest DietPi Trixie)

## Performance Benefits

F2FS provides:
- **Better SD card longevity:** Optimized for flash storage
- **Compression:** Saves space and reduces writes (if enabled)
- **Faster random I/O:** Better than ext4 on SD cards
- **Garbage collection:** Automatic flash-friendly cleanup

## Known Limitations

- Raspberry Pi models older than Pi 3 not tested
- Requires kernel 5.6+ for compression support
- No automated rollback (manual restore from backup needed)
- First boot may be slower due to F2FS initialization

## Support

For issues, see:
- F2FS documentation: https://www.kernel.org/doc/html/latest/filesystems/f2fs.html
- DietPi forums: https://dietpi.com/forum/
- Project repo: https://github.com/yourusername/Linux-OS
