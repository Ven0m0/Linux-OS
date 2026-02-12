# git-fetch - Unified Git File Fetcher

Download files from GitHub repositories OR add them directly to your current git repo.

## Features

- **Dual Mode**: Download files to local directory OR add directly to git repo
- **Smart Conflict Handling**: Skip existing files by default, `--force` to overwrite
- **Parallel Downloads**: Fast concurrent downloads for multiple files
- **Branch/Commit Support**: Fetch from specific branches or commit hashes
- **Auto-Commit**: Optional automatic commit with generated or custom message
- **URL Support**: Parse GitHub URLs directly
- **Folder Support**: Recursively fetch entire directories

## Installation

```bash
# Make executable
chmod +x git-fetch

# Optional: Add to PATH or install as gh extension
ln -s $(pwd)/git-fetch ~/.local/bin/
```

## Usage

### Basic Syntax

```bash
git-fetch [MODE] <repo> <paths...> [OPTIONS]
```

### Modes

- `download` - Download files to local directory (default)
- `add` - Download and add to current git repo

## Examples

### Download Mode

```bash
# Download single file
git-fetch cli/cli README.md

# Download to specific directory
git-fetch cli/cli README.md -o ./docs

# Download multiple files
git-fetch cli/cli LICENSE README.md CODE_OF_CONDUCT.md

# Download from specific branch
git-fetch cli/cli src/ -b develop

# Download from commit hash
git-fetch cli/cli config.yml -c a1b2c3d4

# Download from GitHub URL
git-fetch https://github.com/cli/cli/tree/trunk/docs

# Force overwrite existing files
git-fetch cli/cli README.md --force
```

### Add Mode (Git Integration)

```bash
# Add files to current repo (auto-commit)
git-fetch add cli/cli LICENSE

# Add with custom commit message
git-fetch add cli/cli docs/ -m "docs: Add upstream documentation"

# Add without committing (stage only)
git-fetch add cli/cli README.md --no-commit

# Add and force overwrite existing files
git-fetch add cli/cli config.yml --force -m "config: Update from upstream"
```

## Options Reference

| Option | Description | Default |
|--------|-------------|---------|
| `-b, --branch <name>` | Branch name to fetch from | Repo's default branch |
| `-c, --commit <hash>` | Commit hash to fetch from | - |
| `-o, --output <dir>` | Output directory (download mode) | `.` |
| `-m, --message <msg>` | Commit message (add mode) | Auto-generated |
| `--no-commit` | Skip auto-commit in add mode | Auto-commit enabled |
| `--force` | Overwrite existing files | Skip existing files |
| `-h, --help` | Show help message | - |

## File Conflict Handling

**Default Behavior**: Never overwrite existing files
- Existing files are skipped
- Warning message shows skipped files
- Suggests using `--force` if overwrite intended

**With `--force` flag**: Overwrite all files
- All existing files are replaced
- No confirmation prompt (use carefully!)

```bash
# First download - creates file
git-fetch cli/cli README.md

# Second download - skips file with warning
git-fetch cli/cli README.md
# ⚠ Skipped 1 existing file(s) (use --force to overwrite):
#   README.md

# Third download - overwrites file
git-fetch cli/cli README.md --force
# ✓ README.md (overwritten)
```

## Auto-Commit Behavior

In `add` mode, files are automatically committed by default:

**Default auto-commit message**:
```
Add fetched files from GitHub

Files:
- LICENSE
- README.md

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Custom commit message**:
```bash
git-fetch add cli/cli docs/ -m "docs: Sync documentation from upstream"
```

**Skip auto-commit**:
```bash
git-fetch add cli/cli config.yml --no-commit
# Files are staged, you commit manually when ready
git commit -m "config: Update configuration"
```

## Advanced Examples

### Fetch Multiple Folders

```bash
git-fetch cli/cli docs/ examples/ tests/ -o ./vendor
```

### Add From Specific Branch

```bash
git-fetch add microsoft/vscode src/vs/base/ -b release/1.85
```

### Fetch and Review Before Commit

```bash
# Stage files without committing
git-fetch add cli/cli pkg/ --no-commit

# Review changes
git diff --cached

# Commit when ready
git commit -m "feat: Add upstream packages"
```

### URL-Based Workflow

```bash
# Browse GitHub, copy URL, paste to fetch
git-fetch https://github.com/torvalds/linux/tree/master/kernel
```

## Comparison with Original Scripts

| Feature | git-fetch | gh-download.sh | gh-cp.sh | git-fetch.py | gh-tools.sh |
|---------|-----------|----------------|----------|--------------|-------------|
| Download files | ✅ | ✅ | ✅ | ✅ | ❌ |
| Add to git repo | ✅ | ❌ | ❌ | ❌ | ❌ |
| Auto-commit | ✅ | ❌ | ❌ | ❌ | ❌ |
| Parallel downloads | ✅ | ✅ | ❌ | ✅ | ❌ |
| URL parsing | ✅ | ✅ | ❌ | ✅ | ❌ |
| Branch support | ✅ | ✅ | ✅ | ✅ | ❌ |
| Commit support | ✅ | ❌ | ✅ | ✅ | ❌ |
| Force overwrite | ✅ | ❌ | ❌ | ❌ | ❌ |
| Skip existing | ✅ | ❌ | ❌ | ❌ | ❌ |
| Color output | ✅ | ❌ | ❌ | ❌ | ✅ |

## Migration Guide

### From gh-download.sh

```bash
# Old
gh download owner/repo path/to/file.txt

# New (backward compatible)
git-fetch owner/repo path/to/file.txt
```

### From gh-cp.sh

```bash
# Old
gh cp owner/repo path/to/file.txt -b develop

# New
git-fetch owner/repo path/to/file.txt -b develop
```

### From git-fetch.py

```bash
# Old
python3 git-fetch.py https://github.com/owner/repo/tree/main/src ./output

# New
git-fetch https://github.com/owner/repo/tree/main/src -o ./output
```

## Troubleshooting

### "No GitHub token. Run: gh auth login"

**Solution**: Authenticate with GitHub CLI
```bash
gh auth login
```

### "Not a git repository. Run: git init"

**Solution**: Initialize git repo or use download mode
```bash
git init  # To initialize repo
# OR
git-fetch download owner/repo file.txt  # Use download mode instead
```

### "Failed to fetch folder contents"

**Possible causes**:
- Repository doesn't exist or is private
- Branch name is incorrect
- Path doesn't exist in repository

**Solution**: Verify repo/branch/path exist
```bash
# Check repository exists
gh repo view owner/repo

# Check branch exists
gh api repos/owner/repo/branches --jq '.[].name'
```

### Parallel downloads failing

**Solution**: Disable parallel mode (future enhancement)
```bash
# Currently parallel is always enabled
# Future: Add --no-parallel flag
```

## Technical Details

### Dependencies

- `gh` - GitHub CLI (authenticated)
- `curl` - HTTP client
- `git` - Version control (add mode only)
- `bash` 4+ - Shell interpreter

### Architecture

- **Helper Functions**: Error handling, logging, colored output
- **URL Parsing**: Extract repo/branch/path from GitHub URLs
- **Authentication**: Uses `gh auth token` for API access
- **Parallel Downloads**: curl's `--parallel` with max 32 concurrent
- **Git Integration**: Safe staging with optional auto-commit

### Performance

- **Parallel downloads**: Up to 32 concurrent connections
- **Connection reuse**: curl's Keep-Alive support
- **Retry logic**: 3 retries with 1s delay for transient failures

### Safety Features

- **Strict mode**: `set -euo pipefail` for error detection
- **File conflict protection**: Never overwrites without `--force`
- **Git safety**: Uses staging area, no direct commits without confirmation
- **Temp directory cleanup**: Automatic cleanup on exit

## Contributing

Found a bug or have a feature request? Please file an issue!

## License

Same license as the parent repository.
