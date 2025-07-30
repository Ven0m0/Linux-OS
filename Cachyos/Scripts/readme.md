# Useful shell stuff

<details>
<summary><b>Bash script template</b></summary>

```bash
#!/usr/bin/env bash
#set -eECuo pipefail
set -euo pipefail
IFS=$'\n\t'
shopt -s nullglob globstar

# Faster sorting and emoji support
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo $WORKDIR
cd $WORKDIR

# Ensure root rights
sudo -v

# Sleep replacement in bash
sleepy() { read -rt 0.1 <> <(:) || :; }
```

</details>

<details>
<summary><b>Colors</b></summary>

```bash
#──────────── Foreground colors ────────────
BLK='\033[30m' # Black
RED='\033[31m' # Red
GRN='\033[32m' # Green
YLW='\033[33m' # Yellow
BLU='\033[34m' # Blue
MGN='\033[35m' # Magenta
CYN='\033[36m' # Cyan
WHT='\033[37m' # White
#──────────── Effects ────────────
DEF='\033[0m'  # Reset to default
BLD='\033[1m'  # Bold / Bright
#──────────── Bright colors ────────────
BRIGHT_RED='\033[91m'
BRIGHT_GRN='\033[92m'
BRIGHT_YLW='\033[93m'
BRIGHT_BLU='\033[94m'
BRIGHT_MGN='\033[95m'
BRIGHT_CYN='\033[96m'
BRIGHT_WHT='\033[97m'
#────────────────────────
```

</details>

<details>
<summary><b>Config file in bash</b></summary>
  
in the script:

```bash
# Load config (if it exists)
CONFIG_FILE="./config.cfg"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
```
in the config file:

```bash
# ~/config.cfg || ~/config.conf
USERNAME="user"
PORT=8080
DEBUG=true
```

</details>

<details>
<summary><b>IP Stuff</b></summary>

```bash
# Display global/public IP
echo "Your Global IP is: $(curl -s https://api.ipify.org/)"

# Display weather report based on region
location="$(curl -s ipinfo.io/region)"
[[ "$location" != "Bielefeld" ]] && location="Bielefeld"
curl wttr.in/$location?0

# Speedtest DL/UP
down=$(curl -s -o /dev/null -w "%{speed_download}" https://speed.cloudflare.com/__down?bytes=100000000)
awk -v s="$down" 'BEGIN {printf "Download: %.2f Mbps\n", (s*8)/(1024*1024)}'

up=$(dd if=/dev/zero bs=1M count=10 2>/dev/null | \
  curl -s -o /dev/null -w "%{speed_upload}" --data-binary @- https://speed.cloudflare.com/__up)
awk -v s="$up" 'BEGIN {printf "Upload: %.2f Mbps\n", (s*8)/(1024*1024)}'
```

</details>

<details>
<summary><b>Misc</b></summary>

```bash
# shopt -s extglob
# For 
# *.(jpg|png)
# file?(.*) # file and file.bak
```

</details>
