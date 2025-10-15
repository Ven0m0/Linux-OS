#!/usr/bin/env bash
# Install ZSH configuration for Arch Linux
# This script installs the ultimate Arch ZSH setup

set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar
export LC_ALL=C LANG=C LANGUAGE=C

# ──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'

# ──────────── Helpers ────────────
has(){ command -v -- "$1" >/dev/null 2>&1; }
p(){ printf '%s\n' "$*" 2>/dev/null; }
pe(){ printf '%b\n' "$*"$'\e[0m' 2>/dev/null; }

# ──────────── Configuration ────────────
SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

ZSH_CONFIG_SOURCE="${SCRIPT_DIR}/files/Home/.config/zsh"
ZSH_CONFIG_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
ZSHENV_TARGET="$HOME/.zshenv"

# ──────────── Main Installation ────────────
main(){
  pe "${BLD}${CYN}╔════════════════════════════════════════════════╗${DEF}"
  pe "${BLD}${CYN}║  Ultimate Arch ZSH Configuration Installer     ║${DEF}"
  pe "${BLD}${CYN}╚════════════════════════════════════════════════╝${DEF}"
  echo

  # Check if ZSH is installed
  if ! has zsh; then
    pe "${RED}✗${DEF} ZSH is not installed."
    pe "${YLW}→${DEF} Install it with: ${BLD}sudo pacman -S zsh${DEF}"
    exit 1
  fi

  pe "${GRN}✓${DEF} ZSH is installed: ${BLD}$(zsh --version)${DEF}"
  echo

  # Backup existing configuration
  if [[ -d "$ZSH_CONFIG_TARGET" ]]; then
    local backup_dir="${ZSH_CONFIG_TARGET}.backup.$(date +%Y%m%d-%H%M%S)"
    pe "${YLW}⚠${DEF} Backing up existing ZSH config to:"
    pe "  ${BLD}${backup_dir}${DEF}"
    mv "$ZSH_CONFIG_TARGET" "$backup_dir"
  fi

  if [[ -f "$ZSHENV_TARGET" ]]; then
    local backup_file="${ZSHENV_TARGET}.backup.$(date +%Y%m%d-%H%M%S)"
    pe "${YLW}⚠${DEF} Backing up existing .zshenv to:"
    pe "  ${BLD}${backup_file}${DEF}"
    mv "$ZSHENV_TARGET" "$backup_file"
  fi

  # Create target directory
  mkdir -p "$(dirname "$ZSH_CONFIG_TARGET")"

  # Copy configuration files
  pe "${BLU}→${DEF} Installing ZSH configuration files..."
  cp -r "$ZSH_CONFIG_SOURCE" "$ZSH_CONFIG_TARGET"
  pe "${GRN}✓${DEF} Configuration files copied to: ${BLD}${ZSH_CONFIG_TARGET}${DEF}"

  # Create .zshenv in home directory
  pe "${BLU}→${DEF} Creating ~/.zshenv..."
  cat > "$ZSHENV_TARGET" << 'EOF'
# Set ZDOTDIR to XDG-compliant location
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

# Source the main zshenv if it exists
[[ -f "$ZDOTDIR/zshenv.zsh" ]] && source "$ZDOTDIR/zshenv.zsh"
EOF
  pe "${GRN}✓${DEF} Created: ${BLD}${ZSHENV_TARGET}${DEF}"
  echo

  # Install recommended packages
  pe "${BLD}${YLW}Recommended packages:${DEF}"
  pe "  ${BLD}Core plugins:${DEF}"
  pe "    pacman -S zsh-completions zsh-syntax-highlighting zsh-autosuggestions zsh-history-substring-search"
  pe "  ${BLD}Modern tools:${DEF}"
  pe "    paru -S eza bat ripgrep fd dust bottom zoxide fzf"
  pe "  ${BLD}Optional:${DEF}"
  pe "    paru -S neofetch fastfetch inxi"
  echo

  read -p "Install recommended packages now? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    if has paru; then
      paru -S --needed --noconfirm \
        zsh-completions zsh-syntax-highlighting zsh-autosuggestions \
        zsh-history-substring-search eza bat ripgrep fd dust bottom \
        zoxide fzf neofetch fastfetch inxi 2>/dev/null || true
    elif has yay; then
      yay -S --needed --noconfirm \
        zsh-completions zsh-syntax-highlighting zsh-autosuggestions \
        zsh-history-substring-search eza bat ripgrep fd dust bottom \
        zoxide fzf neofetch fastfetch inxi 2>/dev/null || true
    elif has pacman; then
      sudo pacman -S --needed --noconfirm \
        zsh-completions zsh-syntax-highlighting zsh-autosuggestions \
        zsh-history-substring-search 2>/dev/null || true
      pe "${YLW}⚠${DEF} Some packages may be in AUR. Install with an AUR helper."
    fi
    pe "${GRN}✓${DEF} Packages installed"
    echo
  fi

  # Set ZSH as default shell
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    pe "${YLW}Current shell:${DEF} ${BLD}${SHELL}${DEF}"
    read -p "Set ZSH as default shell? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      chsh -s "$(command -v zsh)"
      pe "${GRN}✓${DEF} ZSH set as default shell"
      echo
    fi
  else
    pe "${GRN}✓${DEF} ZSH is already your default shell"
    echo
  fi

  # Done
  pe "${BLD}${GRN}╔════════════════════════════════════════════════╗${DEF}"
  pe "${BLD}${GRN}║  Installation Complete!                        ║${DEF}"
  pe "${BLD}${GRN}╚════════════════════════════════════════════════╝${DEF}"
  echo
  pe "${BLD}Next steps:${DEF}"
  pe "  1. Log out and log back in (or restart your terminal)"
  pe "  2. Enjoy your new ZSH configuration!"
  pe "  3. Run ${BLD}${CYN}zsh${DEF} to start using it now"
  echo
  pe "Documentation: ${BLD}${ZSH_CONFIG_TARGET}/README.md${DEF}"
  echo
}

main "$@"
