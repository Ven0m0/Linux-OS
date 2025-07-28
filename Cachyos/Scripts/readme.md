# Useful shell stuff


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
