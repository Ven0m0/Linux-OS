# Tput check
#──────────── Color & Effects ────────────
if command -v tput >/dev/null 2>&1 && [ -n "$TERM" ] && tput setaf 0 >/dev/null 2>&1; then
    # tput-based
    DEF=$(tput sgr0)
    BLD=$(tput bold)
    DIM=$(tput dim)
    UND=$(tput smul)
    INV=$(tput rev)
    HID=$(tput invis)

    BLK=$(tput setaf 0)  RED=$(tput setaf 1)  GRN=$(tput setaf 2)  YLW=$(tput setaf 3)
    BLU=$(tput setaf 4)  MGN=$(tput setaf 5)  CYN=$(tput setaf 6)  WHT=$(tput setaf 7)
    BBLK=$(tput setaf 8) BRED=$(tput setaf 9) BGRN=$(tput setaf 10) BYLW=$(tput setaf 11)
    BBLU=$(tput setaf 12) BMGN=$(tput setaf 13) BCYN=$(tput setaf 14) BWHT=$(tput setaf 15)

    BG_BLK=$(tput setab 0)  BG_RED=$(tput setab 1)  BG_GRN=$(tput setab 2)  BG_YLW=$(tput setab 3)
    BG_BLU=$(tput setab 4)  BG_MGN=$(tput setab 5)  BG_CYN=$(tput setab 6)  BG_WHT=$(tput setab 7)
    BG_BBLK=$(tput setab 8) BG_BRED=$(tput setab 9) BG_BGRN=$(tput setab 10) BG_BYLW=$(tput setab 11)
    BG_BBLU=$(tput setab 12) BG_BMGN=$(tput setab 13) BG_BCYN=$(tput setab 14) BG_BWHT=$(tput setab 15)
else
    # ANSI fallback
    DEF='\033[0m'   BLD='\033[1m'   DIM='\033[2m'   UND='\033[4m'
    INV='\033[7m'   HID='\033[8m'
    BLK='\033[30m'  RED='\033[31m'  GRN='\033[32m'  YLW='\033[33m'
    BLU='\033[34m'  MGN='\033[35m'  CYN='\033[36m'  WHT='\033[37m'
    BBLK='\033[90m' BRED='\033[91m' BGRN='\033[92m' BYLW='\033[93m'
    BBLU='\033[94m' BMGN='\033[95m' BCYN='\033[96m' BWHT='\033[97m'
    BG_BLK='\033[40m'  BG_RED='\033[41m'  BG_GRN='\033[42m'  BG_YLW='\033[43m'
    BG_BLU='\033[44m'  BG_MGN='\033[45m'  BG_CYN='\033[46m'  BG_WHT='\033[47m'
    BG_BBLK='\033[100m' BG_BRED='\033[101m' BG_BGRN='\033[102m' BG_BYLW='\033[103m'
    BG_BBLU='\033[104m' BG_BMGN='\033[105m' BG_BCYN='\033[106m' BG_BWHT='\033[107m'
fi
