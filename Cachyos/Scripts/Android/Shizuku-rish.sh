#!/data/data/com.termux/files/usr/bin/bash

adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS

LC_ALL=C LANG=C
BASEDIR=$( dirname "${0}" )
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
DEX="${BASEDIR}/rish_shizuku.dex"

# Exit if dex is not in the same directory
if [ ! -f "${DEX}" ]; then
  echo "Cannot find ${DEX}"
  exit 1
fi

# Create a Shizuku script file
tee "${BIN}/shizuku" > /dev/null << EOF
#!/data/data/com.termux/files/usr/bin/bash

# Make a list of open ports
ports=\$( nmap -sT -p30000-50000 --open localhost | grep "open" | cut -f1 -d/ )

# Go through the list of ports
for port in \${ports}; do

  # Try to connect to the port, and save the result
  result=\$( adb connect "localhost:\${port}" )

  # Check if the connection succeeded
  if [[ "\$result" =~ "connected" || "\$result" =~ "already" ]]; then

    # Show a message to a user
    echo "\${result}"

    # Start Shizuku
    adb shell "\$( adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\\.apk/lib\\/arm64\\/libshizuku\\.so/' )"

    # Disable wireless debugging, because it is not needed anymore
    adb shell settings put global adb_wifi_enabled 0

    exit 0
  fi
done

# If no working ports are found, give an error message to a user
echo "ERROR: No port found! Is wireless debugging enabled?"

exit 1
EOF

# Set the dex location to a variable
dex="${HOME}/rish_shizuku.dex"

# Create a Rish script file
tee "${BIN}/rish" > /dev/null << EOF
#!/data/data/com.termux/files/usr/bin/bash

[ -z "\$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux"

/system/bin/app_process -Djava.class.path="${dex}" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF

# Give execution permission to script files
chmod +x "${BIN}/shizuku" "${BIN}/rish"

# Copy dex to the home directory
cp -f "${DEX}" "${dex}"

# Remove dex write permission, because app_process cannot load writable dex
chmod -w "${dex}"

