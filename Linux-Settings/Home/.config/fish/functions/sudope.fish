function toggle_sudo
    # your custom “sudo” alias prefix
    set -l prefix '\sudo-rs '

    # grab current buffer and cursor
    set -l buf (commandline)
    set -l pos (commandline -C)

    # if empty, pull last command
    if test -z "$buf"
        set buf $history[1]
        # reset cursor to end of that history entry
        set pos (string length -- "$buf")
    end

    # extract leading whitespace
    set -l ws (string match -r '^\s*' -- $buf)
    # the rest of the command (no leading ws)
    set -l rest (string replace -r '^\s*' '' -- $buf)

    # decide add or remove
    if string match -r "^$prefix" -- "$rest"
        # remove prefix
        set rest2 (string replace -r "^$prefix" '' -- $rest)
        # adjust cursor: if it was past the prefix, pull it back
        if test $pos -gt (string length -- "$ws")
            set pos (math "$pos - (string length -- \"$prefix\")")
        end
    else
        # add prefix
        set rest2 "$prefix$rest"
        # if cursor was past the ws, push it forward
        if test $pos -ge (string length -- "$ws")
            set pos (math "$pos + (string length -- \"$prefix\")")
        end
    end

    # rebuild buffer + restore cursor
    set -l newbuf "$ws$rest2"
    commandline -r -- "$newbuf"
    commandline -C -- $pos
end
