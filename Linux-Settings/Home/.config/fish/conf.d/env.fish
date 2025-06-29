# Configuration environment variables

# XDG
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_CACHE_HOME "$HOME/.cache"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx XDG_STATE_HOME "$HOME/.local/state"

# Qt 6
set -gx QT_QPA_PLATFORMTHEME qt6ct
set -gx QT_AUTO_SCREEN_SCALE_FACTOR 0

# Fzf
set -gx FZF_LEGACY_KEYBINDINGS 0

# JetBrains IDE
set -gx _JAVA_AWT_WM_NONREPARENTING 1
set -gx _JAVA_OPTIONS '-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true'

# Firefox
set -gx MOZ_USE_XINPUT2 1
set -gx MOZ_ENABLE_WAYLAND 1
