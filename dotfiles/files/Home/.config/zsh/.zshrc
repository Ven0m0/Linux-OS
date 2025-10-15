#!/usr/bin/env zsh
# .zshrc - Main ZSH configuration file
# This is the entry point for interactive ZSH shells

# ──────────── Performance Tracking (Optional) ────────────
# Uncomment the following lines to profile zsh startup time
# zmodload zsh/zprof
# PROFILE_STARTUP=true

# ──────────── Load Environment Variables ────────────
# Source zshenv if not already loaded
if [[ -f "${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}/zshenv.zsh" ]]; then
  source "${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}/zshenv.zsh"
fi

# ──────────── Load Interactive Configuration ────────────
# Source zshrc.zsh for interactive shell setup
if [[ -f "${ZDOTDIR}/zshrc.zsh" ]]; then
  source "${ZDOTDIR}/zshrc.zsh"
fi

# ──────────── Show Startup Time (Optional) ────────────
# if [[ "$PROFILE_STARTUP" == true ]]; then
#   zprof
# fi
