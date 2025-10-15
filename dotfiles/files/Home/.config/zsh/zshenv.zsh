#!/usr/bin/env zsh
# zshenv.zsh - Environment variables for zsh
# This file is sourced on all invocations of the shell.
# It should NOT produce output or assume the shell is attached to a TTY.

# ──────────── XDG Base Directory Specification ────────────
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"

# ──────────── ZSH Configuration ────────────
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"
export ZSH_CACHE_DIR="${XDG_CACHE_HOME}/zsh"
export ZSH_COMPDUMP="${ZSH_CACHE_DIR}/.zcompdump"

# Create cache directory if it doesn't exist
[[ ! -d "$ZSH_CACHE_DIR" ]] && mkdir -p "$ZSH_CACHE_DIR"

# ──────────── History ────────────
export HISTFILE="${XDG_STATE_HOME}/zsh/history"
export HISTSIZE=50000
export SAVEHIST=50000

# Create history directory if it doesn't exist
[[ ! -d "${HISTFILE:h}" ]] && mkdir -p "${HISTFILE:h}"

# ──────────── Editor & Pager ────────────
export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-nano}"
export PAGER="${PAGER:-less}"

# ──────────── Less Configuration ────────────
export LESS="-R -F -X -i -M -w -z-4"
export LESS_TERMCAP_mb=$'\e[1;31m'     # begin bold
export LESS_TERMCAP_md=$'\e[1;36m'     # begin blink
export LESS_TERMCAP_me=$'\e[0m'        # reset bold/blink
export LESS_TERMCAP_so=$'\e[01;44;33m' # begin reverse video
export LESS_TERMCAP_se=$'\e[0m'        # reset reverse video
export LESS_TERMCAP_us=$'\e[1;32m'     # begin underline
export LESS_TERMCAP_ue=$'\e[0m'        # reset underline

# ──────────── Locale ────────────
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# ──────────── Path Configuration ────────────
typeset -U path  # Keep only unique entries in path
path=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/.cargo/bin"
  "$HOME/.npm-global/bin"
  /usr/local/bin
  /usr/bin
  /bin
  /usr/local/sbin
  /usr/sbin
  /sbin
  $path
)
export PATH

# ──────────── Man Path ────────────
typeset -U manpath
manpath=(
  "$HOME/.local/share/man"
  /usr/local/share/man
  /usr/share/man
  $manpath
)
export MANPATH

# ──────────── Rust Configuration ────────────
export CARGO_HOME="${XDG_DATA_HOME}/cargo"
export RUSTUP_HOME="${XDG_DATA_HOME}/rustup"

# ──────────── Node/NPM Configuration ────────────
export NPM_CONFIG_USERCONFIG="${XDG_CONFIG_HOME}/npm/npmrc"
export NODE_REPL_HISTORY="${XDG_STATE_HOME}/node/repl_history"

# ──────────── Python Configuration ────────────
export PYTHONSTARTUP="${XDG_CONFIG_HOME}/python/pythonrc"
export PYTHONUSERBASE="${XDG_DATA_HOME}/python"
export PYTHONPYCACHEPREFIX="${XDG_CACHE_HOME}/python"

# ──────────── GnuPG Configuration ────────────
export GNUPGHOME="${XDG_DATA_HOME}/gnupg"

# ──────────── Docker Configuration ────────────
export DOCKER_CONFIG="${XDG_CONFIG_HOME}/docker"

# ──────────── Wget Configuration ────────────
export WGETRC="${XDG_CONFIG_HOME}/wget/wgetrc"

# ──────────── GTK Configuration ────────────
export GTK2_RC_FILES="${XDG_CONFIG_HOME}/gtk-2.0/gtkrc"

# ──────────── Arch/Pacman specific ────────────
export PKGEXT=".pkg.tar.zst"
export SRCEXT=".src.tar.gz"

# ──────────── Build Flags (Performance) ────────────
# Optimize for native CPU architecture
export CFLAGS="-march=native -O3 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-Wl,-O3,--sort-common,--as-needed,-z,relro,-z,now,-z,pack-relative-relocs"
export RUSTFLAGS="-C opt-level=3 -C target-cpu=native -C link-arg=-fuse-ld=mold"

# Use all available cores for compilation
export MAKEFLAGS="-j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# ──────────── Preferred Tools ────────────
# Prefer Rust alternatives when available
export BAT_THEME="TwoDark"
export BAT_STYLE="plain"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info --color=dark"
export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME}/ripgrep/config"

# ──────────── Terminal Configuration ────────────
export TERM="${TERM:-xterm-256color}"
export COLORTERM="truecolor"

# ──────────── Compilation Database ────────────
export CMAKE_EXPORT_COMPILE_COMMANDS=ON

# ──────────── GPG TTY ────────────
export GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"

# ──────────── SSH Agent ────────────
if [[ -z "$SSH_AUTH_SOCK" ]]; then
  export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.socket"
fi

# ──────────── Disable files ────────────
export LESSHISTFILE=-
export MYSQL_HISTFILE="${XDG_STATE_HOME}/mysql/history"
export SQLITE_HISTORY="${XDG_STATE_HOME}/sqlite/history"

# ──────────── QT Wayland ────────────
export QT_QPA_PLATFORM="wayland;xcb"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1

# ──────────── Mozilla ────────────
export MOZ_ENABLE_WAYLAND=1

# ──────────── Performance Tuning ────────────
# Limit memory usage
export NODE_OPTIONS="--max-old-space-size=4096"

# Enable parallel builds
export NINJAFLAGS="-j$(nproc 2>/dev/null || echo 4)"
