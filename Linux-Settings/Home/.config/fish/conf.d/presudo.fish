function toggle_sudo
  set line (commandline)
  if test -z "$line"
    set line (history | head -n1 | string trim)
    if string match -r '^sudo ' -- "$line" > /dev/null
      set line (string replace -r '^sudo\s+' '' -- "$line")
    else
      set line "sudo $line"
    end
  else if string match -r '^sudo ' -- "$line" > /dev/null
    set line (string replace -r '^sudo\s+' '' -- "$line")
  else
    set line "sudo $line"
  end
  commandline --replace -- "$line"
end

# Bind double Esc to toggle_sudo
bind \e\e toggle_sudo
