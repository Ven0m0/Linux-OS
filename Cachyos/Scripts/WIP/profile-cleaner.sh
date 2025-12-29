#!/bin/bash
# Compact Profile Cleaner - Optimized
# shellcheck disable=2034,2155

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
VERSION="2.0"

# --- Configuration & Colors ---
CONFIG="$XDG_CONFIG_HOME/profile-cleaner.conf"
[[ -f "$CONFIG" ]] && . "$CONFIG"
if [[ "${COLORS:-dark}" == "dark" ]]; then
    BLD="\e[1m" RED="\e[1;31m" GRN="\e[1;32m" YLW="\e[1;33m" NRM="\e[0m"
else
    BLD="\e[1m" RED="\e[0;31m" GRN="\e[0;32m" YLW="\e[0;34m" NRM="\e[0m"
fi

printf "${BLD}profile-cleaner v%s${NRM}\n\n" "$VERSION"

# --- Dependency Check ---
for cmd in bc find parallel sqlite3 xargs file; do
    command -v "$cmd" >/dev/null || { echo >&2 "Missing dependency: $cmd"; exit 1; }
done

# --- Core Functions ---
export GRN YLW NRM

do_clean_file() {
    local db="$1"
    local bsize=$(du -b "$db" | cut -f1)
    
    printf "${GRN} Cleaning${NRM} %s" "${db##*/}"
    sqlite3 "$db" "VACUUM; REINDEX;"
    
    local asize=$(du -b "$db" | cut -f1)
    local saved=$(echo "scale=2; ($bsize-$asize)/1048576" | bc)
    printf "\r\033[K${GRN} Done${NRM} -${YLW}%s${NRM} MB\n" "$saved"
}
export -f do_clean_file

run_parallel() {
    local targets=("$@")
    [[ ${#targets[@]} -eq 0 ]] && return
    
    local total_start=$(du -b -c "${targets[@]}" | tail -n 1 | cut -f 1)
    
    # Run in parallel
    SHELL=/bin/bash parallel --gnu -k --bar do_clean_file ::: "${targets[@]}" 2>/dev/null
    
    local total_end=$(du -b -c "${targets[@]}" | tail -n 1 | cut -f 1)
    local total_saved=$(echo "scale=2; ($total_start-$total_end)/1048576" | bc)
    
    printf "\n${BLD}Total reduced by ${YLW}%s${NRM}${BLD} MB.${NRM}\n\n" "$total_saved"
}

find_dbs() {
    # Finds files, checks if they are SQLite, filters out WAL files
    find -L "$@" -maxdepth 2 -type f -not -name '*.sqlite-wal' -print0 2>/dev/null | \
        xargs -0 file -e ascii | \
        sed -n 's/:.*SQLite.*//p'
}

# Wrapper to handle different browser detection strategies
# Usage: scan_and_clean [type] [name_for_display] [base_path] [subdirs...]
scan_and_clean() {
    local type="$1"
    local name="$2"
    local base="$3"
    shift 3
    local subdirs=("$@")
    local paths_to_clean=()

    printf " ${YLW}Checking %s...${NRM}\n" "$name"

    if [[ "$type" == "chrome" ]]; then
        for dir in "${subdirs[@]}"; do
            [[ -d "$base/$dir" ]] && paths_to_clean+=("$base/$dir")
        done
        [[ ${#paths_to_clean[@]} -eq 0 ]] && { echo -e "${RED}Error: No profiles found for $name in $base${NRM}"; exit 1; }

    elif [[ "$type" == "mozilla" ]]; then
        [[ ! -d "$base" ]] && { echo -e "${RED}Error: Directory $base not found${NRM}"; exit 1; }
        [[ ! -f "$base/profiles.ini" ]] && { echo -e "${RED}Error: profiles.ini not found for $name${NRM}"; exit 1; }
        
        # Extract paths from profiles.ini
        while read -r path_line; do
            local p_path="${path_line#*=}"
            # Handle relative vs absolute paths in ini
            [[ -d "$base/$p_path" ]] && paths_to_clean+=("$base/$p_path") || paths_to_clean+=("$p_path")
        done < <(grep '^[Pp]ath=' "$base/profiles.ini" | tr -d '\r')

    elif [[ "$type" == "path" ]] || [[ "$type" == "simple" ]]; then
        # 'simple' expects base to be the profile dir; 'path' expects args to be dirs
        if [[ "$type" == "simple" ]]; then
            [[ -d "$base" ]] && paths_to_clean+=("$base")
        else
            for p in "$base" "${subdirs[@]}"; do
                 [[ -d "$p" ]] && paths_to_clean+=("$p")
            done
        fi
        [[ ${#paths_to_clean[@]} -eq 0 ]] && { echo -e "${RED}Error: Invalid path(s) provided${NRM}"; exit 1; }
    fi

    # Execute cleaning
    mapfile -t targets < <(find_dbs "${paths_to_clean[@]}")
    run_parallel "${targets[@]}"
}

# --- Main Logic ---

case "$1" in
    # Chrome/Chromium Based
    B|b)  scan_and_clean chrome "Brave" "$XDG_CONFIG_HOME/BraveSoftware" Brave-Browser{,-Dev,-Beta,-Nightly} ;;
    C|c)  scan_and_clean chrome "Chromium" "$XDG_CONFIG_HOME" chromium{,-beta,-dev} ;;
    E|e)  scan_and_clean chrome "Edge" "$XDG_CONFIG_HOME" microsoft-edge ;;
    GC|gc) scan_and_clean chrome "Google Chrome" "$XDG_CONFIG_HOME" google-chrome{,-beta,-unstable} ;;
    ix|IX) scan_and_clean chrome "Inox" "$XDG_CONFIG_HOME" inox ;;
    O|o)  scan_and_clean chrome "Opera" "$XDG_CONFIG_HOME" opera{,-next,-developer,-beta} ;;
    V|v)  scan_and_clean chrome "Vivaldi" "$XDG_CONFIG_HOME" vivaldi{,-snapshot} ;;

    # Mozilla/XUL Based
    F|f)  scan_and_clean mozilla "Firefox" "$HOME/.mozilla/firefox" ;;
    H|h)  scan_and_clean mozilla "Aurora" "$HOME/.mozilla/aurora" ;;
    I|i)  scan_and_clean mozilla "Icecat" "$HOME/.mozilla/icecat" ;;
    ID|id) scan_and_clean mozilla "Icedove" "$HOME/.icedove" ;; # Common location
    L|l)  scan_and_clean mozilla "Librewolf" "$HOME/.librewolf" ;;
    PM|pm) scan_and_clean mozilla "Pale Moon" "$HOME/.moonchild productions/pale moon" ;;
    S|s)  scan_and_clean mozilla "Seamonkey" "$HOME/.mozilla/seamonkey" ;;
    T|t)  scan_and_clean mozilla "Thunderbird" "$HOME/.thunderbird" ;;
    CK|ck) scan_and_clean mozilla "Conkeror" "$HOME/.conkeror.mozdev.org/conkeror" ;;
    # Simple DB Based
    FA|fa) scan_and_clean simple "Falkon" "$HOME/.config/falkon/profiles" ;;
    M|m)   scan_and_clean simple "Midori" "$XDG_CONFIG_HOME/midori" ;;
    n|N)   
        # Newsboat handles XDG or Home
        nb_path="$HOME/.newsboat"
        [[ -d "$XDG_DATA_HOME/newsboat" ]] && nb_path="$XDG_DATA_HOME/newsboat"
        scan_and_clean simple "Newsboat" "$nb_path" 
        ;;
    Q|q)   scan_and_clean simple "QupZilla" "$HOME/.config/qupzilla/profiles" ;;
    # Special Cases
    TO|to)
        # Handle Tor Browser's varied install paths
        base="$HOME/.torbrowser/profile"
        for lang in de en es fr it ru; do
            [[ ! -d "$base" ]] && base="$HOME/.tor-browser-$lang/INSTALL/Data/profile"
        done
        scan_and_clean simple "TorBrowser" "$base"
        ;;
    P|p) 
        shift
        scan_and_clean path "Custom Paths" "$@" 
        ;;
    *)
        echo -e "Usage: $0 {browser_code}"
        echo -e "\nChrome-based: ${GRN}b${NRM}rave, ${GRN}c${NRM}hromium, ${GRN}e${NRM}dge, ${GRN}gc${NRM}hrome, ${GRN}o${NRM}pera, ${GRN}v${NRM}ivaldi, ${GRN}ix${NRM}nox"
        echo -e "Mozilla-based: ${GRN}f${NRM}irefox, ${GRN}t${NRM}hunderbird, ${GRN}l${NRM}ibrewolf, ${GRN}pm${NRM}oon, ${GRN}s${NRM}eamonkey, ${GRN}i${NRM}cecat"
        echo -e "Others: ${GRN}fa${NRM}lkon, ${GRN}m${NRM}idori, ${GRN}n${NRM}ewsboat, ${GRN}to${NRM}rbrowser, ${GRN}p${NRM}aths (custom)"
        exit 0
        ;;
esac
