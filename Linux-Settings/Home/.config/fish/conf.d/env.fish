# Configuration environment variables

# XDG
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_CACHE_HOME "$HOME/.cache"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx XDG_STATE_HOME "$HOME/.local/state"

# Qt 6
#set -gx QT_QPA_PLATFORMTHEME qt6ct

# Fzf
set -gx FZF_LEGACY_KEYBINDINGS 0

if [ $XDG_SESSION_TYPE = "wayland" ]
    set -x SDL_VIDEODRIVER wayland
    set -x QT_QPA_PLATFORM wayland
    set -x MOZ_ENABLE_XINPUT2 1
    set -x MOZ_ENABLE_WAYLAND 1
    set -x GDK_BACKEND wayland
end

# JetBrains IDE
set -gx _JAVA_OPTIONS '-Dawt.useSystemAAFontSettings=on -Dswing.aatext=true'

# Rust
set -gx RUSTC_WRAPPER sccache
set -gx RUST_LOG off
set -gx CARGO_HTTP_MULTIPLEXING true
set -gx CARGO_NET_GIT_FETCH_WITH_CLI true
set -gx CARGO_HTTP_SSL_VERSION tlsv1.3
set -gx CARGO_REGISTRIES_CRATES_IO_PROTOCOL sparse
# Git
set -gx GITOXIDE_CORE_MULTIPACKINDEX true
set -gx GITOXIDE_HTTP_SSLVERSIONMAX tls1.3
set -gx GITOXIDE_HTTP_SSLVERSIONMIN tls1.2

