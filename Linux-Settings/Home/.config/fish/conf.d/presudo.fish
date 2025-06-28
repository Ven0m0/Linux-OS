function toggle_sudo
    # Get current command line contents
    set line (commandline)
    if test -z "$line"
        # If command line empty, get last command from history and trim whitespace
        set line (history | head -n1 | string trim)
        # If it starts with sudo, remove it; else prepend sudo
        if string match -r '^sudo ' -- "$line"
            set line (string replace -r '^sudo\s+' '' -- "$line")
        else
            set line "sudo $line"
        end
    else
        # If current command line starts with sudo, remove it; else prepend sudo
        if string match -r '^sudo ' -- "$line"
            set line (string replace -r '^sudo\s+' '' -- "$line")
        else
            set line "sudo $line"
        end
    end
    # Replace current command line with modified command
    commandline --replace -- "$line"
end

bind \e\e toggle_sudo
