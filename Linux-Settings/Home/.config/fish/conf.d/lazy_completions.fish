# ─── Only run in interactive sessions ─────────────────────────────────────────
if not status --is-interactive
    return
end

# ─── Commands with disabled completions ───────────────────────────────────────
set -l lazy_completion_cmds fisher procs rg

for cmd in $lazy_completion_cmds
    set -l compfile "$__fish_config_dir/completions/$cmd.fish"
    set -l disabled "$compfile.disabled"

    if test -f $compfile -a ! -f $disabled
        mv $compfile $disabled
    end

    # Define stub function to load real completions on demand
    set -l fnname "__lazy_${cmd}_completions"
    functions -q $fnname; or function $fnname --description "lazy‑load $cmd completions"
        complete -c $cmd -e
        source $disabled
        functions -e $fnname
        commandline -f repaint
    end

    complete -c $cmd -f -a "($fnname)"
end

# ─── Lazy-load fzf on first call ──────────────────────────────────────────────
function fzf --description "lazy-load fzf"
    functions -e fzf
    fzf --fish | source
    commandline -f repaint
    fzf $argv
end

# ─── Lazy-load pay-respects on first use ──────────────────────────────────────
function pay-respects --description "lazy-load pay-respects fish aliases"
    functions -e pay-respects
    pay-respects fish --alias | source
    commandline -f repaint
    pay-respects $argv
end
