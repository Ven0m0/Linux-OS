# Ultimate Arch ZSH Configuration

A comprehensive, performance-optimized ZSH configuration designed for Arch Linux systems with a focus on speed, usability, and modern tooling.

## Features

- **XDG Base Directory compliant** - Keeps your home directory clean
- **Performance optimized** - Fast startup with lazy loading and caching
- **Modern tooling** - Integrates with Rust-based CLI tools (eza, bat, rg, fd, etc.)
- **Git integration** - Shows git status in prompt with branch and changes
- **Comprehensive aliases** - Shortcuts for common tasks and package management
- **Smart completion** - Case-insensitive, fuzzy matching with cache
- **History management** - Persistent, shared history across sessions
- **Safety features** - Interactive prompts for destructive operations

## Installation

### Quick Install

1. Copy the configuration files to your home directory:
   ```bash
   cp -r dotfiles/files/Home/.config/zsh ~/.config/
   ```

2. Set ZSH as your default shell:
   ```bash
   chsh -s /bin/zsh
   ```

3. Create the `~/.zshenv` symlink or file:
   ```bash
   echo 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"' > ~/.zshenv
   echo '[[ -f "$ZDOTDIR/zshenv.zsh" ]] && source "$ZDOTDIR/zshenv.zsh"' >> ~/.zshenv
   ```

4. Log out and log back in.

### Recommended Packages (Arch Linux)

Install these packages for the best experience:

```bash
# Core ZSH plugins
paru -S zsh zsh-completions zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search

# Rust-based modern CLI tools
paru -S eza bat ripgrep fd dust bottom zoxide

# Optional but recommended
paru -S fzf neofetch fastfetch inxi
```

## File Structure

- **`.zshrc`** - Main entry point, sources other config files
- **`zshenv.zsh`** - Environment variables and XDG setup
- **`zshrc.zsh`** - Interactive shell configuration (aliases, functions, prompt)
- **`zlogin`** - Login shell initialization (system info, updates check)
- **`.zshrc.local`** - Machine-specific configuration (create if needed, not tracked)
- **`.zlogin.local`** - Machine-specific login config (create if needed, not tracked)

## Configuration

### Environment Variables

Key environment variables set in `zshenv.zsh`:

- `ZDOTDIR` - ZSH config directory (`~/.config/zsh`)
- `XDG_*` - XDG base directory specification
- `HISTFILE` - History file location
- `EDITOR` - Default text editor
- `CFLAGS/CXXFLAGS` - Build optimization flags for native CPU

### Custom Configuration

Create `~/.config/zsh/.zshrc.local` for machine-specific aliases and functions:

```bash
# Example .zshrc.local
export MY_CUSTOM_VAR="value"
alias myalias='command'
```

Create `~/.config/zsh/.zlogin.local` for machine-specific login tasks:

```bash
# Example .zlogin.local
# Custom login message or tasks
```

## Key Bindings

### Emacs-style (default)

- `Ctrl+A` - Beginning of line
- `Ctrl+E` - End of line
- `Ctrl+U` - Delete to beginning of line
- `Ctrl+K` - Delete to end of line
- `Ctrl+W` / `Alt+Backspace` - Delete word backward
- `Ctrl+R` - History search
- `Up/Down` - History substring search
- `Ctrl+Left/Right` - Word navigation

### Vi-style (optional)

To enable vi-style key bindings, edit `zshrc.zsh` and change:
```bash
bindkey -e  # to  bindkey -v
```

## Aliases

### File Operations

- `ls` → `eza` (if available) with icons and git integration
- `cat` → `bat` (if available) with syntax highlighting
- `grep` → `rg` (ripgrep, if available)
- `find` → `fd` (if available)
- `du` → `dust` (if available)
- `cd` → `z` (zoxide, if available) for smart directory jumping

### Package Management (Arch)

- `p` - Package manager (paru/yay/pacman)
- `pi` - Install package
- `pr` - Remove package
- `prs` - Remove package with dependencies
- `pu` - Update system
- `ps` - Search packages
- `pq` - Query installed packages
- `pc` - Clean package cache

### Git

- `g` - git
- `ga` - git add
- `gaa` - git add --all
- `gc` - git commit
- `gcm` - git commit -m
- `gco` - git checkout
- `gd` - git diff
- `gst` - git status
- `gp` - git push
- `gl` - git pull
- `glg` - git log --oneline --graph

### Navigation

- `..` - cd ..
- `...` - cd ../..
- `....` - cd ../../..
- `.....` - cd ../../../..

## Functions

### Useful Functions

- `mkcd <dir>` - Create directory and cd into it
- `extract <file>` - Extract various archive formats
- `bak <file>` - Create timestamped backup
- `dsort [n]` - List largest directories (default: 20)
- `sysupdate` - Update system packages
- `sysclean` - Clean package cache and orphans

### Fuzzy Functions (requires fzf)

- `fcd [dir]` - Fuzzy find and cd to directory
- `fvim` - Fuzzy find and edit file
- `fgco` - Fuzzy git checkout branch
- `fkill` - Fuzzy find and kill process

## Prompt

The prompt shows:
- Username and hostname
- Current directory (with colors)
- Git branch and status (if in git repo)
  - Green dot: staged changes
  - Yellow dot: unstaged changes
- Command success/failure indicator (green/red arrow)
- Current time on the right

Example:
```
╭─user@hostname ~/projects/myproject (main●●)
╰─❯ 
```

## Performance

### Startup Time

Optimizations for fast startup:
- Completion cache (recompiled only once per day)
- Lazy loading of plugins
- Efficient history management
- Minimal external command execution

Typical startup time: 50-150ms

### Profiling

To profile startup time, uncomment these lines in `.zshrc`:
```bash
zmodload zsh/zprof
# ... (rest of config)
zprof
```

## Troubleshooting

### Slow Startup

1. Check startup time with profiling (see above)
2. Disable plugins one by one in `zshrc.zsh`
3. Clear completion cache: `rm -rf ${ZSH_CACHE_DIR}/*`

### Completion Not Working

1. Rebuild completion cache:
   ```bash
   rm -f ${ZSH_COMPDUMP}
   compinit
   ```

2. Check plugin installation:
   ```bash
   ls /usr/share/zsh/plugins/
   ```

### History Not Saving

Check permissions:
```bash
ls -la ${HISTFILE}
chmod 600 ${HISTFILE}
```

## Resources

- [ZSH Documentation](https://zsh.sourceforge.io/Doc/)
- [Arch Wiki - ZSH](https://wiki.archlinux.org/title/Zsh)
- [Oh My ZSH](https://ohmyz.sh/) - Alternative framework
- [Prezto](https://github.com/sorin-ionescu/prezto) - Alternative framework

## Contributing

Feel free to customize and improve this configuration. Key principles:
- Keep it fast
- Keep it simple
- Keep it maintainable
- Document changes

## License

This configuration is part of the Linux-OS repository and follows the same license.
