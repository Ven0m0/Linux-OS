# Dotfiles

Configuration files and dotfiles for various applications and shells.

## Contents

- **files/Home/.config/zsh/** - Ultimate Arch ZSH configuration
  - See [ZSH README](files/Home/.config/zsh/README.md) for detailed documentation

## Quick Install

### ZSH Configuration

To install the ZSH configuration, run:

```bash
./install-zsh-config.sh
```

Or manually:

```bash
# Copy configuration files
cp -r files/Home/.config/zsh ~/.config/

# Create ~/.zshenv
cat > ~/.zshenv << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/zshenv.zsh" ]] && source "$ZDOTDIR/zshenv.zsh"
EOF

# Set ZSH as default shell
chsh -s $(command -v zsh)
```

## Features

### ZSH Configuration

- ✅ XDG Base Directory compliant
- ✅ Performance optimized (50-150ms startup)
- ✅ Modern tooling integration (eza, bat, rg, fd, zoxide, etc.)
- ✅ Git integration in prompt
- ✅ Comprehensive aliases and functions
- ✅ Smart completion with cache
- ✅ Persistent history management
- ✅ Safety features (interactive prompts for rm, cp, mv)

### Architecture

```
dotfiles/
├── install-zsh-config.sh          # Installation script
├── README.md                       # This file
└── files/
    └── Home/
        └── .config/
            └── zsh/
                ├── .zshrc          # Main entry point
                ├── zshenv.zsh      # Environment variables
                ├── zshrc.zsh       # Interactive configuration
                ├── zlogin          # Login shell initialization
                └── README.md       # Detailed ZSH documentation
```

## Requirements

### ZSH Configuration

**Required:**
- `zsh` - The Z Shell

**Recommended:**
- `zsh-completions` - Additional completion definitions
- `zsh-syntax-highlighting` - Syntax highlighting
- `zsh-autosuggestions` - Fish-like autosuggestions
- `zsh-history-substring-search` - Better history search

**Optional (Modern Tools):**
- `eza` - Modern replacement for ls
- `bat` - Cat with syntax highlighting
- `ripgrep` - Fast grep alternative
- `fd` - Fast find alternative
- `dust` - Better du
- `bottom` - System monitor
- `zoxide` - Smarter cd
- `fzf` - Fuzzy finder
- `neofetch` / `fastfetch` - System information

### Installation (Arch Linux)

```bash
# Core packages
paru -S zsh zsh-completions zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search

# Modern tools
paru -S eza bat ripgrep fd dust bottom zoxide fzf neofetch fastfetch inxi
```

## Usage

### ZSH

After installation, log out and log back in, or start a new shell:

```bash
zsh
```

See the [ZSH README](files/Home/.config/zsh/README.md) for detailed usage instructions, aliases, functions, and customization options.

## Customization

### Local Configuration

Create machine-specific configuration files that won't be tracked:

```bash
# Interactive shell customization
~/.config/zsh/.zshrc.local

# Login shell customization
~/.config/zsh/.zlogin.local
```

Example `.zshrc.local`:
```bash
# Custom aliases
alias myproject='cd ~/projects/myproject'

# Custom environment variables
export MY_VAR="value"

# Custom functions
myfunc() {
  echo "Hello from custom function"
}
```

## Contributing

Feel free to customize and improve these dotfiles. When adding new configurations:

1. Follow XDG Base Directory specification
2. Keep performance in mind
3. Document new features
4. Test on a clean system
5. Follow the coding style from `.github/copilot-instructions.md`

## Related Resources

- [Arch Wiki - Dotfiles](https://wiki.archlinux.org/title/Dotfiles)
- [Arch Wiki - ZSH](https://wiki.archlinux.org/title/Zsh)
- [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)
- [Main Repository](../)
