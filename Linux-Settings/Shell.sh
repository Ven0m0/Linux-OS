#!/usr/bin/env bash
# Crabfetch instead of fastfetch

sudo sed -i '/^function fish_greeting$/,/^end$/ {
    /^ *fastfetch$/c\
    \    crabfetch --config=preset:neofetch -d arch || fastfetch
}' /usr/share/cachyos-fish-config/cachyos-config.fish



# Addline function: add a line to a file if the line doesn't already exist
addline(){ LC_ALL=C command grep -qxF "$2" "$1" || echo "$2" >> "$1"; }
# Example:
# addline .bashrc "alias cd='z'"
