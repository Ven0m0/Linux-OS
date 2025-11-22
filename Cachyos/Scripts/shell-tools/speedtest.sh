# Download
down=$(curl -sf4 -o /dev/null -w "%{speed_download}" https://speed.cloudflare.com/__down?bytes=100000000)
awk -v s="$down" 'BEGIN {printf "Download: %.2f Mbps\n", (s*8)/(1024*1024)}'

# Upload (10 MB)
up=$(dd if=/dev/zero bs=1M count=10 2> /dev/null \
  | curl -sf4 -o /dev/null -w "%{speed_upload}" --data-binary @- https://speed.cloudflare.com/__up)
awk -v s="$up" 'BEGIN {printf "Upload: %.2f Mbps\n", (s*8)/(1024*1024)}'
