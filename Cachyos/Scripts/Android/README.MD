# Android Optimization Scripts

A collection of unified, deduplicated scripts for Android device optimization, APK optimization, and system maintenance.

## 🚀 Main Scripts

### `android-optimize.sh` - Unified Android Optimizer
The primary tool for device optimization with a CLI interface. This script combines multiple optimization workflows into one unified tool.

**Commands:**
```bash
# Full device optimization pipeline
./android-optimize.sh device-all

# Compile all apps (monolith optimization)
./android-optimize.sh monolith [mode]        # default: everything-profile

# Clear app caches
./android-optimize.sh cache-clean

# Create .nomedia/.noindex files recursively
./android-optimize.sh index-nomedia [path]   # default: /storage/emulated/0

# Clean old WhatsApp media (>45 days)
./android-optimize.sh wa-clean [path]

# Optimize APK with aapt2
./android-optimize.sh aapt2-opt [input.apk] [output.apk]
```

**What `device-all` does:**
- Device maintenance (fstrim, cleanup, cache trimming)
- Filesystem cleanup (removes temp files, logs, backups)
- ART optimization (dex compilation with speed-profile + speed modes)
- Performance tweaks (CPU/GPU boost, high refresh rate)
- Rendering tweaks (GPU acceleration, composition optimization)
- Audio tweaks (offload, hardware codecs)
- Battery optimization (power savings, app restrictions)
- Input/animation tweaks (reduced latency, disabled animations)
- Network optimization (data saver, background restrictions)
- WebView/ANGLE configuration
- App-specific compilation (speed mode for performance apps, everything mode for system apps)

---

### `adb-experimental-tweaks.sh` - Experimental System Tweaks
**⚠️ WARNING: Very aggressive experimental tweaks. Use at your own risk!**

This script contains 1000+ system property and settings changes. It's comprehensive but potentially unstable. Only use if you understand the implications.

```bash
./adb-experimental-tweaks.sh
```

---

### `optimize_apk.sh` - Comprehensive APK Optimization
Full APK optimization pipeline with resource stripping, bytecode optimization, and repackaging.

**Requirements:** apktool, redex, dex2jar, proguard/R8, zipalign, apksigner, pngcrush, jpegoptim, 7z

```bash
./optimize_apk.sh input.apk output.apk
```

**Process:**
1. Decode APK with apktool
2. Strip unused resources (extra densities, raw files, assets)
3. Rebuild stripped APK
4. Run Redex optimization
5. Convert DEX to JAR for ProGuard/R8
6. Run ProGuard shrinking
7. Rebuild DEX from optimized JAR
8. Align APK
9. Sign APK
10. Optimize PNGs and JPEGs

---

### `termux-butler.sh` - Termux Environment Maintenance
Interactive maintenance tool for Termux environments.

```bash
./termux-butler.sh
```

**Features:**
- Package updates and cache cleaning
- Application cache cleanup (pip, npm, user cache)
- Filesystem hygiene (remove empty files/dirs)
- Find large files
- Update locate database

---

## 🔧 Utility Scripts

### `setup.sh` - Quick Shizuku Permission Grant
```bash
./setup.sh
```
Grants WRITE_SECURE_SETTINGS permission to Shizuku API.

---

### `Shizuku-rish.sh` - Shizuku Setup
Sets up Shizuku and Rish (root shell) in Termux.

**Requirements:** nmap, Shizuku app, wireless debugging enabled

```bash
./Shizuku-rish.sh
```

Creates:
- `/data/data/com.termux/files/usr/bin/shizuku` - Shizuku launcher
- `/data/data/com.termux/files/usr/bin/rish` - Root shell command

---

### `mkshrc.sh` - Enhanced Shell Configuration
Shell configuration for mksh (Android's default shell).

**Features:**
- Enhanced keybindings (Ctrl+arrows, history search)
- Useful aliases for package manager, logcat, navigation
- Custom functions (current_activity, myip, man replacement)
- Colorized prompt with exit status indicator

**Usage:**
```bash
# Copy to your shell RC file
cat mkshrc.sh >> ~/.mkshrc
source ~/.mkshrc
```

---

## 📚 Additional Resources

### Better 'adb shell'
- https://github.com/matan-h/adb-shell
- [mkshrc configuration](mkshrc.sh)
- https://github.com/trinhnv1205/optimize

### WebView & Browser Flags
- [WebView flags](https://github.com/celenityy/configs/blob/pages/android/webview-flags.md)
- [Chromium flags](https://gist.github.com/ibLeDy/1495735312943b9dd646fd9ddf618513)

### Debloating Tools
- [Adbloat](https://github.com/YurinDoctrine/adbloat)
- [UAD-NG](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation)

### Other Tools
- https://github.com/Parsa307/split_optimizer
- [Termux SSH Setup](https://github.com/tomhiggins/TermuxSSHDsetup)

---

## 🎮 Quick Tips

### Game Mode
```bash
# Enable fixed performance mode (game on)
adb shell cmd power set-fixed-performance-mode-enabled true

# Disable (normal use)
adb shell cmd power set-fixed-performance-mode-enabled false
```

### Write Stats to Disk
```bash
adb shell cmd stats write-to-disk
```

### Remote Install (index guard)
```bash
curl -sSfL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/Cachyos/Scripts/Android/android-optimize.sh | bash -s index-nomedia
```

---

## 📝 Notes

- Always backup your device before running optimization scripts
- Some scripts require USB debugging enabled
- Some features require root access
- The experimental tweaks script is very aggressive - review before use
- Test optimizations on non-critical devices first

---

## 🔗 TODO

- https://modules.lsposed.org/
- https://github.com/trinhnv1205/optimize/blob/main/menu/fullscreen_immersive_getsure.sh (might fix 3-button navigation bar)
- https://github.com/LeNerd46/SpotifyPlus
- https://github.com/7723mod/NPatch
- https://github.com/pumPCin/AntiSplit-M
- https://github.com/ReSo7200/InstaEclipse
- https://github.com/android-hacker/VirtualXposed
- https://github.com/risin42/NagramX
- https://github.com/Nahvine/ADB_Toolbox
- https://github.com/Th3-R3p4ck3r/ApkPatcher
- https://github.com/TechnoIndian/ApkPatcher

TODO: fork this repo and optimize it (merge it into a single python script and add graphicsmagick)
- https://github.com/charwasp/modify/
