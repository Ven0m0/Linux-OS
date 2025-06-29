# ~/.config/fish/conf.d/lazy_completions.fish

# ─── only in interactive sessions ─────────────────────────────────────────────
if not status --is-interactive
    return
end

# ─── list of commands to lazy‑load completions for ─────────────────────────────
set -l commands fisher fzf_configure_bindings procs rg

for cmd in $commands
    set -l compfile $HOME/.config/fish/completions/$cmd.fish
    set -l disabled  $compfile.disabled

    # ─── disable the real completion on first run ───────────────────────────────
    if test -f $compfile -a ! -f $disabled
        mv $compfile $disabled
    end

    # ─── one‑shot loader function ──────────────────────────────────────────────
    function __lazy_${cmd}_completions --description "lazy‑load $cmd completions"
        complete -c $cmd -e                     # remove this stub
        source $disabled                       # load the real completions
        functions -e __lazy_${cmd}_completions # drop this loader
        commandline -f repaint                 # retry the TAB immediately
    end

    # ─── stub out the real options until first TAB ─────────────────────────────
    complete -c $cmd -f -a "(__lazy_${cmd}_completions)"
end
