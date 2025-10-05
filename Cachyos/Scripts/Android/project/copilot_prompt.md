# GitHub Copilot Workspace Generation Prompt

## Objective
Create a comprehensive data management workspace containing multiple specialized Bash scripts for Android device cleaning and media compression tasks. The workspace should be well-structured, thoroughly documented, and modular for easy maintenance and use.

## Workspace Structure Request

Generate a workspace with the following structure:
```
data-management-toolkit/
├── README.md
├── config/
│   ├── compression-settings.conf
│   └── cleaning-whitelist.conf
├── scripts/
│   ├── android-cleaner.sh
│   ├── media-compressor.sh
│   ├── whatsapp-cleaner.sh
│   └── utils/
│       ├── logging.sh
│       ├── backup-manager.sh
│       └── dependency-checker.sh
├── logs/
├── backups/
└── examples/
    ├── sample-config.conf
    └── usage-examples.md
```

## Script Requirements

### 1. Android Device Cleaner (`android-cleaner.sh`)
Create a comprehensive Android cleaning script with these specifications:
- **Primary Function**: Remove junk data from Android devices while preserving essential files
- **Shell Compatibility**:
  - Support Termux bash environment natively
  - Auto-detect and adapt for `adb shell` (mksh) execution
  - Compatible with Shizuku `rish` for elevated permissions
  - Fallback to POSIX-compliant commands when necessary
- **Performance Optimization**:
  - Use `fd` command instead of `find` when available (much faster)
  - Implement parallel processing for large directory scans
  - Optimize for Android filesystem characteristics
- **Safety Features**:
  - Mandatory backup creation before any deletion
  - Interactive confirmation for critical operations
  - Whitelist system for protected directories and files
  - Dry-run mode for preview of actions
- **Cleaning Targets**:
  - Per-app cache clearing (both third-party and system apps using `pm clear --cache-only`)
  - System-wide cache trimming using `pm trim-caches`
  - Cache directories (`/sdcard/Android/data/*/cache/`)
  - Temporary files (`*.tmp`, `*.temp`, `*~`)
  - Log files (`*.log`) and backup files (`*.bak`, `*.old`, `*.json.bak`)
  - Android system logs using `logcat -b all -c`
  - Duplicate files (with user confirmation)
  - Empty directories
  - Browser cache and downloads
- **Shizuku Integration**:
  - Auto-start Shizuku API: `adb shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.api`
  - Grant necessary permissions: `adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS`
  - Use elevated permissions for system-level cleaning operations
- **WhatsApp Integration**: Call specialized WhatsApp cleaner as a module
- **Logging**: Comprehensive logging of all operations with timestamps
- **Progress Indicators**: Visual progress bars for long operations

### 2. WhatsApp Folder Cleaner (`whatsapp-cleaner.sh`)
Specialized script for WhatsApp data management:
- **Target Directories**:
  - `/sdcard/WhatsApp/` (legacy path)
  - `/sdcard/Android/media/com.whatsapp/WhatsApp/` (standard path)
  - `/data/data/com.termux/files/home/storage/shared/Android/media/com.whatsapp/WhatsApp/Media` (Termux path)
  - Auto-detect available paths and prioritize accessible ones
- **Cross-Platform Execution**:
  - Full Termux bash support with native Android filesystem access
  - `adb shell` (mksh) compatibility with proper command adaptations
  - Shizuku `rish` integration for system-level access when needed
  - Efficient file operations using `fd` command where available
- **Protected Files**:
  - Active chat databases (`.db.crypt14`, `.db.crypt15`)
  - Recent media files (within last 30 days)
  - Starred/important media (check metadata)
- **Cleaning Operations**:
  - Remove duplicate media files across all chat folders
  - Clean old status/story files (older than 24 hours)
  - Remove corrupted/incomplete downloads
  - Clean voice note cache
  - Remove old backup files (keep latest 3)
  - Clean temporary profile pictures
- **Smart Detection**: Identify and preserve profile pictures, group icons, and wallpapers
- **Media Preservation**: Maintain original file extensions and folder structure
- **Size Reporting**: Display space savings after cleaning

### 3. Media Compressor (`media-compressor.sh`)
Advanced media compression script with Rust-based tools preference:
- **Compression Tools** (in order of preference):
  - **Video**: `av1an` (AV1), `rav1e`, `svt-av1`, `x265`, `vpxenc` (VP9)
  - **Audio**: `opusenc`, `oggenc`, `lame` (fallback)
  - **Images**: `cavif-rs`, `cwebp`, `oxipng`, `mozjpeg`
- **Compression Profiles**:
  - **Ultra Quality**: Visually lossless, larger file sizes
  - **High Quality**: Minimal quality loss, balanced compression
  - **Balanced**: Good quality with significant size reduction
  - **Aggressive**: Maximum compression with acceptable quality loss
- **Video Compression**:
  - Primary codec: AV1 (using `av1an` with `rav1e` or `svt-av1`)
  - Secondary: VP9 (using `vpxenc`)
  - Fallback: H.265/HEVC (using `x265`)
  - Preserve HDR metadata and audio tracks
  - Multi-threaded processing with CPU core detection
- **Audio Compression**:
  - Primary: Opus codec (`opusenc`)
  - Bitrates: 128kbps (speech), 192kbps (music), 256kbps (high quality)
  - Preserve metadata and chapters
- **Image Compression**:
  - **WhatsApp folder**: Maintain original extensions (JPG→JPG, PNG→PNG)
  - **Other locations**: Convert to AVIF (primary) or WebP (fallback)
  - Smart quality adjustment based on image content
  - Preserve EXIF data for photos
- **Advanced Features**:
  - Batch processing with parallel jobs
  - Progress tracking and ETA calculation
  - Before/after size comparison
  - Quality metrics reporting (PSNR, SSIM when possible)
  - Resume interrupted operations

### 4. Utility Scripts (`utils/`)

#### Logging Module (`logging.sh`)
- Structured logging with levels (DEBUG, INFO, WARN, ERROR)
- Automatic log rotation
- Color-coded console output
- Log file management with size limits

#### Backup Manager (`backup-manager.sh`)
- Incremental backup system
- Compression of backup archives
- Automatic cleanup of old backups
- Verification of backup integrity

#### Dependency Checker (`dependency-checker.sh`)
- Check for required tools and their versions
- Automatic installation prompts for missing dependencies
- Alternative tool suggestions when primary tools unavailable
- Performance benchmarking for compression tools

## Configuration Files

### Compression Settings (`config/compression-settings.conf`)
```bash
# Video compression settings
VIDEO_CODEC_PRIMARY="av1"
VIDEO_CODEC_SECONDARY="vp9"
VIDEO_CODEC_FALLBACK="h265"
VIDEO_CRF_ULTRA=15
VIDEO_CRF_HIGH=20
VIDEO_CRF_BALANCED=25
VIDEO_CRF_AGGRESSIVE=30

# Audio compression settings
AUDIO_CODEC="opus"
AUDIO_BITRATE_SPEECH=128
AUDIO_BITRATE_MUSIC=192
AUDIO_BITRATE_HIGH=256

# Image compression settings
IMAGE_FORMAT_PRIMARY="avif"
IMAGE_FORMAT_SECONDARY="webp"
IMAGE_QUALITY_ULTRA=95
IMAGE_QUALITY_HIGH=85
IMAGE_QUALITY_BALANCED=75
IMAGE_QUALITY_AGGRESSIVE=65
```

### Cleaning Whitelist (`config/cleaning-whitelist.conf`)
```bash
# Protected directories (never delete)
PROTECTED_DIRS=(
    "/sdcard/DCIM"
    "/sdcard/Download"
    "/sdcard/Documents"
    "/sdcard/WhatsApp/Databases"
)

# Protected file patterns
PROTECTED_PATTERNS=(
    "*.db.crypt*"
    "msgstore*.db"
    "wa.db"
    "*.nomedia"
)
```

## Technical Requirements

### Shell Compatibility & Environment Detection
- **Auto-detect execution environment**: Termux, ADB shell (mksh), or standard Linux
- **Termux Native Support**: Full bash feature utilization in Termux environment
- **mksh Compatibility**: Adapt script syntax for `adb shell` (Android's mksh)
- **Shizuku Integration**: Support `rish` commands for elevated operations
- **POSIX Fallbacks**: Ensure core functionality works with basic POSIX shell
- **Environment Variables**: Detect and set appropriate PATH and tool locations

### Performance Optimization & Tool Preferences
- **Prefer `fd` over `find`**: Use `fd-find` command when available for faster file operations
- **Rust-based Tools Priority**: Favor Rust implementations (faster, safer)
- **Parallel Processing**: Multi-threaded operations where safe and beneficial
- **Memory Efficiency**: Monitor usage for large operations on Android devices
- **Efficient Algorithms**: Optimize for Android filesystem characteristics
- **Smart Caching**: Cache results for repeated operations

### Error Handling & Safety
- Comprehensive error checking with meaningful error messages
- Rollback capabilities for critical operations
- User confirmation for destructive operations
- Graceful handling of permission issues
- Signal handling (CTRL+C) with proper cleanup

### User Experience
- Interactive menus with clear options
- Real-time progress indicators
- Estimated time remaining for long operations
- Summary reports after completion
- Colored output for better readability

### Compatibility & Dependencies
- **Termux Support**: Full compatibility with Termux bash environment
- **Android Shell Compatibility**: Support for both `adb shell` (mksh) and Shizuku `rish`
- **Cross-shell scripting**: Auto-detect shell type (bash/mksh) and adapt accordingly
- **Performance Tools**: Prefer `fd` over `find` for file operations when available
- Support for both Android device cleaning (via ADB) and direct filesystem access
- Graceful degradation when advanced tools unavailable
- Dependency installation guides for major Linux distributions and Termux
- Compatibility checks for different Android versions

### Documentation Requirements
- Comprehensive README with installation and usage instructions
- Inline code comments explaining complex operations
- Example usage scenarios
- Troubleshooting guide
- Performance tuning recommendations

## Advanced Features to Include

### Intelligent File Detection
- MIME type detection for accurate file classification
- Duplicate detection using hash comparison
- Corruption detection for media files
- Smart categorization of files by usage patterns

### Monitoring and Reporting
- Space usage analysis before and after operations
- Performance metrics for compression operations
- Detailed operation logs with timestamps
- Export reports in multiple formats (text, JSON, CSV)

### Integration Capabilities
- Plugin system for additional compression tools
- Configuration profiles for different use cases
- Scheduled operation support via cron integration
- Integration with cloud storage services for backups

## Code Implementation Requirements

### Shell Detection & Adaptation
Include shell detection logic like:
```bash
# Detect shell environment and set appropriate commands
detect_shell_environment() {
    if [[ -n "$TERMUX_VERSION" ]]; then
        ENVIRONMENT="termux"
        FIND_CMD="fd"  # Prefer fd in Termux
    elif [[ "$0" == *"adb"* ]] || [[ -n "$ADB_SHELL" ]]; then
        ENVIRONMENT="adb_mksh"
        FIND_CMD="find"  # mksh environment
    elif command -v rish >/dev/null 2>&1; then
        ENVIRONMENT="shizuku"
        FIND_CMD="fd"
    else
        ENVIRONMENT="linux"
        FIND_CMD="fd"
    fi
}
```

### Tool Preference Implementation
```bash
# Smart tool selection with fallbacks
setup_tools() {
    # Prefer fd over find for better performance
    if command -v fd >/dev/null 2>&1; then
        FIND_TOOL="fd"
    elif command -v fdfind >/dev/null 2>&1; then
        FIND_TOOL="fdfind"  # Ubuntu package name
    else
        FIND_TOOL="find"
    fi

    # Set appropriate flags for each environment
    case "$ENVIRONMENT" in
        "adb_mksh")
            # mksh-compatible syntax
            ;;
        "termux"|"shizuku")
            # Full bash features available
            ;;
    esac
}
```

### Priority Requirements
1. **Android Device Cleaner**: Must work in Termux + adb shell + rish
2. **WhatsApp Cleaner**: Must work in Termux + adb shell + rish
3. **Media Compressor**: Lower priority for shell compatibility (can focus on Termux/Linux)

### Shizuku Integration Examples
Include Shizuku initialization and cleaning commands:
```bash
# Initialize Shizuku for elevated operations
init_shizuku() {
    echo "🔧 Starting Shizuku API..."
    adb shell sh /storage/emulated/0/Android/data/moe.shizuku.privileged.api/start.api
    adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS
}

# Advanced cache clearing with Shizuku
clear_app_caches() {
    echo "🔄 Clearing per-app cache (third-party apps)..."
    adb shell pm list packages -3 | cut -d: -f2 \
      | xargs -n1 -I{} adb shell pm clear --cache-only {}

    echo "🔄 Clearing per-app cache (system apps)..."
    adb shell pm list packages -s | cut -d: -f2 \
      | xargs -n1 -I{} adb shell pm clear --cache-only {}

    echo "🧹 Trimming system-wide app caches..."
    adb shell pm trim-caches 128G
}

# Clean system files and logs
clean_system_files() {
    echo "🗑️ Deleting log, backup, and temp files from /sdcard..."
    adb shell 'find /sdcard -type f \( \
        -iname "*.log" -o \
        -iname "*.bak" -o \
        -iname "*.old" -o \
        -iname "*.tmp" -o \
        -iname "*~" -o \
        -iname "*.json.bak" \
      \) -delete'

    echo "📱 Clearing Android system logs..."
    adb logcat -b all -c
}
```

### Performance Optimizations
- Use `fd` command syntax: `fd -t f -e tmp -e temp -x rm`
- Implement parallel processing with `xargs -P` for compatible shells
- Add progress indicators using shell-appropriate methods

Generate this workspace with production-ready code that follows bash best practices, includes comprehensive error handling, provides cross-shell compatibility (bash/mksh), and delivers a user-friendly experience for both Termux and ADB shell environments.

