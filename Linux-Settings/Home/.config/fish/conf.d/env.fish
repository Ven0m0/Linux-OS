# Configuration environment variables

# XDG
set -g -x XDG_CONFIG_HOME "$HOME/.config"
set -g -x XDG_CACHE_HOME "$HOME/.cache"
set -g -x XDG_DATA_HOME "$HOME/.local/share"
set -g -x XDG_STATE_HOME "$HOME/.local/state"

# Qt 6
set -g -x QT_QPA_PLATFORMTHEME qt6ct
set -g -x QT_AUTO_SCREEN_SCALE_FACTOR 0

# Fzf
set -g -x FZF_LEGACY_KEYBINDINGS 0

# JetBrains IDE
set -g -x _JAVA_AWT_WM_NONREPARENTING 1
set -g -x _JAVA_OPTIONS '-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true'

# Firefox
set -x MOZ_USE_XINPUT2 1
set -x MOZ_ENABLE_WAYLAND 1
