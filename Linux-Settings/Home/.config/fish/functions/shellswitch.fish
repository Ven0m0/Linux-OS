function shellswitch
    # Read shells from /etc/shells ignoring comments/empty lines using rg
    set shells (rg --no-filename --no-line-number --invert-match '^(#|$)' /etc/shells)

    if test (count $shells) -eq 0
        echo "No shells found in /etc/shells"
        return 1
    end

    echo "Available shells:"
    for i in (seq (count $shells))
        set shell_name (basename $shells[$i])
        echo "$i) $shell_name"
    end

    while true
        echo -n "Enter shell name or number: "
        read choice

        # Check if choice is number
        if string match -qr '^\d+$' -- $choice
            if test $choice -ge 1 -a $choice -le (count $shells)
                set shell_path $shells[$choice]
                break
            else
                echo "Invalid number, try again."
            end
        else
            # Match shells by basename
            set matches
            for s in $shells
                if test (basename $s) = $choice
                    set matches $matches $s
                end
            end

            if test (count $matches) -eq 1
                set shell_path $matches[1]
                break
            else if test (count $matches) -gt 1
                echo "Multiple shells match '$choice', please enter number."
            else
                echo "No shell matches '$choice', try again."
            end
        end
    end

    echo "Switching to shell: $shell_path"
    exec $shell_path
end
