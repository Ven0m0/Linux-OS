function runch -w "exec" -d "make a script executable and run it"
    # Grab first argument
    set -l s $argv[1]
    # Missing argument?
    if test -z "$s"
        printf 'runch: missing script argument\nUsage: runch <script>\n' >&2
        return 2
    end
    # Make executable (ignore stderr), fail if it doesn’t work
    chmod u+x -- $s ^/dev/null
    or begin
        printf 'runch: cannot make executable: %s\n' $s >&2
        return 1
    end
    # Execute: if path has “/” use as-is, else prefix “./”
    switch $s
        case '*/'*; exec $s
        case '*';     exec "./$s"
    end
end
