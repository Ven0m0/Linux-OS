function batmanurl
    if test (count $argv) -eq 0
        echo "Usage: batmanurl <raw-github-url>"
        return 1
    end

    curl -s "$argv[1]" | bat -l man
end
