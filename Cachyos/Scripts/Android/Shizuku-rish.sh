#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C LANG=C

adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS

BASEDIR="${0%/*}"
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
DEX="${BASEDIR}/rish_shizuku.dex"

# Exit if dex is not in the same directory
if [[ ! -f $DEX ]]; then
  echo "Cannot find ${DEX}"
  exit 1
fi

# Create a Shizuku script file with optimized port detection
tee "${BIN}/shizuku" >/dev/null <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Common wireless debugging ports (try these first for speed)
COMMON_PORTS=(37373 40181 42135 44559)

# Fast port checking function using /dev/tcp (no external tools needed)
check_port(){
  local port="$1"
  timeout 0.5 bash -c "echo>/dev/tcp/127.0.0.1/$port" 2>/dev/null && return 0 || return 1
}

# Try common ports first (much faster than scanning)
for port in "${COMMON_PORTS[@]}"; do
  if check_port "$port"; then
    result=$( adb connect "localhost:${port}" 2>&1 )
    if [[ "$result" =~ "connected" || "$result" =~ "already" ]]; then
      echo "${result}"
      adb shell "$( adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\.apk/lib\/arm64\/libshizuku.so/' )"
      adb shell settings put global adb_wifi_enabled 0
      exit 0
    fi
  fi
done

# Fallback: Use netstat/ss if available (much faster than nmap)
if command -v netstat &>/dev/null; then
  mapfile -t ports < <(netstat -tln | awk '/127\.0\.0\.1:/ && $4 ~ /:3[0-9]{4}|:4[0-9]{4}|:5[0-9]{4}/ {split($4,a,":"); if(a[2]>=30000 && a[2]<=50000) print a[2]}' | sort -u)
elif command -v ss &>/dev/null; then
  mapfile -t ports < <(ss -tln | awk '/127\.0\.0\.1:/ && $4 ~ /:3[0-9]{4}|:4[0-9]{4}|:5[0-9]{4}/ {split($4,a,":"); if(a[2]>=30000 && a[2]<=50000) print a[2]}' | sort -u)
else
  # Last resort: scan ports but with timeout (still faster than nmap)
  ports=()
  echo "Scanning ports 30000-50000 (this may take a moment)..."
  for ((p=30000; p<=50000; p+=100)); do
    # Sample every 100th port for speed
    check_port "$p" && ports+=("$p")
  done
fi

# Try discovered ports
for port in "${ports[@]}"; do
  result=$( adb connect "localhost:${port}" 2>&1 )
  if [[ "$result" =~ "connected" || "$result" =~ "already" ]]; then
    echo "${result}"
    adb shell "$( adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\.apk/lib\/arm64\/libshizuku.so/' )"
    adb shell settings put global adb_wifi_enabled 0
    exit 0
  fi
done

echo "ERROR: No port found! Is wireless debugging enabled?"
exit 1
EOF

# Set the dex location to a variable
dex="${HOME}/rish_shizuku.dex"

# Create a Rish script file
tee "${BIN}/rish" >/dev/null <<EOF
#!/data/data/com.termux/files/usr/bin/bash

[[ -z "\$RISH_APPLICATION_ID" ]] && export RISH_APPLICATION_ID="com.termux"

/system/bin/app_process -Djava.class.path="${dex}" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF

# Give execution permission to script files
chmod +x "${BIN}/shizuku" "${BIN}/rish"

# Copy dex to the home directory
cp -f "$DEX" "$dex"

# Remove dex write permission, because app_process cannot load writable dex
chmod -w "$dex"
