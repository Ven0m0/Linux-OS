#!/bin/sh
# ~/.profile

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ]; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Add cargo binaries to path if it exits
if [ -e "$HOME/.cargo/env" ]; then
	. "$HOME/.cargo/env"
fi

if [ -d "$HOME/.cargo/bin" ]; then
	export PATH="$PATH:$HOME/.cargo/bin"
fi

if [ -f "$HOME/.config/wget/wgetrc" ]; then
  export WGETRC="${WGETRC:=${XDG_CONFIG_HOME:-$HOME/.config}/wget/wgetrc}"
elif [ -f "$HOME/wgetrc" ]; then
  export WGETRC="${WGETRC:=${XDG_CONFIG_HOME:-$HOME}/wgetrc}"
fi
