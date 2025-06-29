function toggle_sudo
    # your custom “sudo” alias prefix
    set -l prefix '\sudo-rs '

    # grab current buffer and cursor
    set -l buf (commandline)
    set -l pos (commandline -C)

    # if empty, pull last command from history
    if test -z "$buf"
        set buf $history[1]
        set pos (string length -- "$buf")
    end

    # extract leading whitespace
    set -l ws (string match -r '^\s*' -- $buf)
    # the rest of the command (no leading ws)
    set -l rest (string replace -r '^\s*' '' -- $buf)

    # toggle prefix
    if string match -r "^$prefix" -- "$rest"
        # remove prefix
        set rest2 (string replace -r "^$prefix" '' -- $rest)
        if test $pos -gt (string length -- "$ws")
            set pos (math "$pos - (string length -- \"$prefix\")")
        end
    else
        # add prefix
        set rest2 "$prefix$rest"
        if test $pos -ge (string length -- "$ws")
            set pos (math "$pos + (string length -- \"$prefix\")")
        end
    end

    # rebuild buffer + restore cursor
    set -l newbuf "$ws$rest2"
    commandline -r -- "$newbuf"
    commandline -C -- $pos
end
