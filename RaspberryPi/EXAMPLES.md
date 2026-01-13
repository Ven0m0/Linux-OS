# DietPi F2FS Conversion Examples

## Quick Start Examples

### 1. Interactive Mode (Recommended for Beginners)

**Scenario:** First-time user wants to convert DietPi to F2FS

```bash
# Launch interactive mode with fzf menus
sudo ./f2fs-new.sh -i

# Follow the prompts:
# 1. Select source: "Download DietPi Trixie (latest)"
# 2. Select output: "Flash to device"
# 3. Select device from list (e.g., /dev/mmcblk0)
# 4. Wait for completion
# 5. Insert SD card into Pi and boot
```

**What happens:**
- Downloads latest DietPi Trixie image
- Converts to F2FS
- Flashes directly to SD card
- Ready to boot

### 2. Create F2FS Image for Later Use

**Scenario:** Convert DietPi image and save for multiple Pi devices

```bash
# Download and convert to F2FS image
sudo ./f2fs-new.sh --out ~/Images/dietpi-f2fs-$(date +%Y%m%d).img

# Later, flash to SD cards as needed
sudo dd if=~/Images/dietpi-f2fs-20260113.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

**What happens:**
- Downloads DietPi image
- Converts to F2FS
- Saves as timestamped image file
- Can be reused for multiple devices

### 3. Convert Local Image

**Scenario:** Already have DietPi image downloaded

```bash
# Convert existing local image
sudo ./f2fs-new.sh --src ~/Downloads/DietPi_RPi234-ARMv8-Trixie.img.xz --out ~/dietpi-f2fs.img

# Or use interactive mode to browse local files
sudo ./f2fs-new.sh -i
# Select: "Local image file"
# Browse and select your image
```

**What happens:**
- Uses local image (no download needed)
- Converts to F2FS
- Saves to specified path

## Advanced Examples

### 4. Custom F2FS Options

**Scenario:** Need different compression algorithm or mount options

```bash
# Use LZ4 compression instead of zstd (faster, less compression)
sudo ./f2fs-new.sh \
  --out ~/dietpi-lz4.img \
  --root-opts "compress_algorithm=lz4,compress_chksum,atgc,gc_merge"

# Disable compression entirely (for older kernels)
sudo ./f2fs-new.sh \
  --out ~/dietpi-nocomp.img \
  --root-opts "defaults,noatime,atgc,gc_merge"

# Maximum performance (aggressive GC)
sudo ./f2fs-new.sh \
  --out ~/dietpi-perf.img \
  --root-opts "compress_algorithm=zstd,atgc,gc_merge,background_gc=on,gc_urgent=high"
```

**What happens:**
- Customizes F2FS mount options in fstab
- Different trade-offs: performance vs. compression vs. compatibility

### 5. Flash Multiple SD Cards

**Scenario:** Setting up multiple Raspberry Pi devices with same image

```bash
# Create master F2FS image once
sudo ./f2fs-new.sh --out ~/master-dietpi-f2fs.img

# Flash to multiple cards
for device in /dev/mmcblk0 /dev/sda /dev/sdb; do
  echo "Flashing $device..."
  sudo dd if=~/master-dietpi-f2fs.img of=$device bs=4M conv=fsync status=progress
done
```

**What happens:**
- Creates one master image
- Reuses it for multiple devices
- Saves download/conversion time

### 6. Using raspi-f2fs.sh for Advanced Control

**Scenario:** Need shrinking, SSH, or custom boot size

```bash
# Interactive mode
sudo ./raspi-f2fs.sh

# Enable SSH and shrink image
sudo ./raspi-f2fs.sh -i dietpi -d /dev/mmcblk0 -s -z

# Custom boot partition size
sudo ./raspi-f2fs.sh -i dietpi -d /dev/mmcblk0 -b 1G

# Use local image with all features
sudo ./raspi-f2fs.sh -i ~/dietpi.img.xz -d /dev/mmcblk0 -s -z -b 512M
```

**Options:**
- `-s`: Enable SSH on first boot
- `-z`: Shrink image before flashing
- `-b SIZE`: Set boot partition size
- `-k`: Keep source image (don't delete after use)

### 7. Post-Conversion Customization

**Scenario:** Need to modify image before flashing

```bash
# Create F2FS image
sudo ./f2fs-new.sh --out ~/dietpi-f2fs.img

# Chroot into image for customization
sudo ./dietpi-chroot.sh ~/dietpi-f2fs.img

# Inside chroot:
apt update
apt install -y vim htop
systemctl enable ssh
exit

# Now flash customized image
sudo dd if=~/dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

**What happens:**
- Creates F2FS image
- Chroots for customization
- Automatically regenerates initramfs
- Flashes customized image

### 8. Batch Conversion

**Scenario:** Convert multiple DietPi images to F2FS

```bash
#!/bin/bash
# Convert all .img.xz files in current directory

for img in *.img.xz; do
  name="${img%.img.xz}"
  echo "Converting $img..."
  sudo ./f2fs-new.sh --src "$img" --out "${name}_f2fs.img"
done
```

**What happens:**
- Finds all compressed images
- Converts each to F2FS
- Outputs with `_f2fs` suffix

### 9. Network Installation

**Scenario:** Download and flash from remote server

```bash
# Custom URL
sudo ./f2fs-new.sh \
  --src "https://mirror.example.com/dietpi-custom.img.xz" \
  --device /dev/mmcblk0

# Interactive mode with custom URL
sudo ./f2fs-new.sh -i
# Select: "Custom URL"
# Enter: https://mirror.example.com/dietpi-custom.img.xz
```

**What happens:**
- Downloads from custom URL
- Converts to F2FS
- Flashes directly to device

### 10. Testing and Verification

**Scenario:** Test F2FS conversion before production deployment

```bash
# Create test image
sudo ./f2fs-new.sh --out /tmp/test-f2fs.img

# Verify image structure
sudo ./dietpi-chroot.sh /tmp/test-f2fs.img

# Inside chroot:
# Check fstab
cat /etc/fstab | grep f2fs

# Check cmdline
cat /boot/cmdline.txt | grep rootfstype=f2fs

# Check F2FS module
ls -la /lib/modules/*/kernel/fs/f2fs/

# Exit
exit

# Flash to test device
sudo dd if=/tmp/test-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

**What happens:**
- Creates test image
- Verifies F2FS configuration
- Checks all required components
- Flashes for boot testing

## Troubleshooting Examples

### 11. Recovery from Failed Boot

**Scenario:** Pi won't boot after F2FS conversion

```bash
# Method 1: Regenerate initramfs
sudo ./dietpi-chroot.sh /dev/mmcblk0p2  # Or image file

# Inside chroot:
update-initramfs -u
exit

# Method 2: Check F2FS module
sudo ./dietpi-chroot.sh /dev/mmcblk0p2

# Inside chroot:
echo "f2fs" >> /etc/initramfs-tools/modules
update-initramfs -u
exit
```

### 12. Debugging with Serial Console

**Scenario:** Need boot logs for troubleshooting

```bash
# Enable serial console in cmdline.txt before flashing
sudo ./f2fs-new.sh --out ~/dietpi-f2fs.img

# Mount and modify
mkdir -p /tmp/mnt
sudo mount -o loop,offset=1048576 ~/dietpi-f2fs.img /tmp/mnt
sudo nano /tmp/mnt/cmdline.txt
# Add: console=serial0,115200 console=tty1
sudo umount /tmp/mnt

# Flash and connect serial cable
sudo dd if=~/dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

## Common Workflows

### Workflow A: Development to Production

```bash
# 1. Create development image
sudo ./f2fs-new.sh -i
# Select: Local file → dev-dietpi.img.xz
# Select: Create image file → dev-dietpi-f2fs.img

# 2. Test on development Pi
sudo dd if=dev-dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress

# 3. After testing, customize
sudo ./dietpi-chroot.sh dev-dietpi-f2fs.img
# Install packages, configure services
exit

# 4. Deploy to production Pis
for pi in pi1 pi2 pi3; do
  echo "Deploying to $pi..."
  sudo dd if=dev-dietpi-f2fs.img of=/dev/sd${pi:2:1} bs=4M conv=fsync status=progress
done
```

### Workflow B: Regular Updates

```bash
# 1. Download latest DietPi monthly
cd ~/Images
sudo ./f2fs-new.sh --out dietpi-f2fs-$(date +%Y%m).img

# 2. Create versioned copies
cp dietpi-f2fs-$(date +%Y%m).img dietpi-f2fs-latest.img

# 3. Flash to devices as needed
sudo dd if=dietpi-f2fs-latest.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

### Workflow C: Automated CI/CD

```bash
#!/bin/bash
# ci-build-dietpi-f2fs.sh

set -euo pipefail

DATE=$(date +%Y%m%d)
OUTPUT="dietpi-f2fs-${DATE}.img"
CHECKSUM="${OUTPUT}.sha256"

# Download and convert
sudo ./f2fs-new.sh --out "$OUTPUT"

# Generate checksum
sha256sum "$OUTPUT" > "$CHECKSUM"

# Upload to artifact storage
aws s3 cp "$OUTPUT" "s3://my-bucket/images/"
aws s3 cp "$CHECKSUM" "s3://my-bucket/images/"

echo "Build complete: $OUTPUT"
```

## Tips and Best Practices

### Tip 1: Always Verify Before Mass Deployment

```bash
# Test on one device first
sudo ./f2fs-new.sh -i  # Interactive mode
# Boot and verify F2FS is working
mount | grep "on / type f2fs"

# Then deploy to others
```

### Tip 2: Keep Master Images

```bash
# Create dated masters
sudo ./f2fs-new.sh --out ~/Images/dietpi-master-$(date +%Y%m%d).img

# Keep last 3 months
cd ~/Images && ls -t dietpi-master-*.img | tail -n +4 | xargs rm
```

### Tip 3: Use Compression for Storage

```bash
# Compress master images
xz -9 -T0 dietpi-master-20260113.img
# Decompress when needed
xz -dc dietpi-master-20260113.img.xz | sudo dd of=/dev/mmcblk0 bs=4M status=progress
```

### Tip 4: Parallel Device Flashing

```bash
# Flash multiple devices simultaneously
sudo ./f2fs-new.sh --src dietpi.img.xz --device /dev/mmcblk0 &
sudo ./f2fs-new.sh --src dietpi.img.xz --device /dev/sda &
wait
```

## Script Comparison

| Use Case | Script | Command |
|----------|--------|---------|
| Interactive conversion | f2fs-new.sh | `sudo ./f2fs-new.sh -i` |
| Create image file | f2fs-new.sh | `sudo ./f2fs-new.sh --out image.img` |
| Flash to device | f2fs-new.sh | `sudo ./f2fs-new.sh --device /dev/mmcblk0` |
| Advanced flashing | raspi-f2fs.sh | `sudo ./raspi-f2fs.sh -i dietpi -d /dev/mmcblk0` |
| Post-conversion | dietpi-chroot.sh | `sudo ./dietpi-chroot.sh image.img` |
| Shrink + SSH | raspi-f2fs.sh | `sudo ./raspi-f2fs.sh -i dietpi -d /dev/mmcblk0 -z -s` |
