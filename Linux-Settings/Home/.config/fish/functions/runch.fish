function runch
    set script $argv[1]
    if test -z "$script"
        printf 'chrun: missing script argument\nUsage: chrun <script>\n' >&2
        return 2
    end
    chmod u+x -- "$script" ^/dev/null
    if test $status -ne 0
        printf 'chrun: cannot make executable: %s\n' "$script" >&2
        return 1
    end
    switch "$script"
        case '*/'*      # contains a slash
            exec "$script"
        case '*'        # no slash
            exec "./$script"
    end
end
