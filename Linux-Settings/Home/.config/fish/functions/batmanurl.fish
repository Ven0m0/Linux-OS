function batmanurl -w "man" -d "view a github manpage with bat"
    if test (count $argv) -eq 0
        echo "Usage: batmanurl <github-url>"
        return 1
    end

    # Extract raw URL from GitHub blob URL
    set url $argv[1]
    set raw_url (string replace -r 'https://github.com/([^/]+)/([^/]+)/blob/([^/]+)/(.*)' 'https://raw.githubusercontent.com/$1/$2/$3/$4' $url)

    curl -s "$raw_url" | bat -l man
end
