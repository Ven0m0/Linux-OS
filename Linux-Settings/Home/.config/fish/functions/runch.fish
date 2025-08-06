function runch -d "make a script executable and run it"
    # Grab the first argument
    set -l s $argv[1]

    # Missing argument?
    if test -z "$s"
        printf 'runch: missing script argument\nUsage: runch <script>\n' >&2
        return 2
    end

    # Try to chmod, silencing stderr; bail if it fails
    chmod u+x -- "$s" 2>/dev/null; or begin
        printf 'runch: cannot make executable: %s\n' "$s" >&2
        return 1
    end

    # Exec: if there’s a slash, run as-is; otherwise prefix "./"
    switch "$s"
        case '*/'*; exec "$s"
        case '*';     exec "./$s"
    end
end
