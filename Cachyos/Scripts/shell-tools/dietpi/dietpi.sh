# Returns current CPU temp 'C
# - print_full_info=1	Optional input to print full colour text output and temp warnings
G_OBTAIN_CPU_TEMP(){
  # Read CPU temp from file
  local temp
  # - Odroid N2/ASUS/Sparky: Requires special case as in other array this would break SBC temp readouts with 2 zones
  if [[ ($G_HW_MODEL == 15 || $G_HW_MODEL == 52 || $G_HW_MODEL == 70) && -f '/sys/class/thermal/thermal_zone1/temp' ]]; then
    read -r temp < /sys/class/thermal/thermal_zone1/temp

  # - Others
  else
    # Array to store possible locations for temp read
    local i afp_temperature=(

      '/sys/devices/platform/coretemp.[0-9]/hwmon/hwmon[0-9]/temp[1-9]_input' # Intel Mini PCs: https://github.com/MichaIng/DietPi/issues/3172, https://github.com/MichaIng/DietPi/issues/3412
      '/sys/class/thermal/thermal_zone0/temp'
      '/sys/devices/platform/sunxi-i2c.0/i2c-0/0-0034/temp1_input'
      '/sys/class/hwmon/hwmon0/device/temp_label'
      '/sys/class/hwmon/hwmon0/temp2_input'
      '/sys/class/hwmon/hwmon0/temp1_input'   # Odroid C1 Armbian legacy Linux 5.4.40: https://dietpi.com/phpbb/viewtopic.php?p=24860#p24860
      '/sys/class/thermal/thermal_zone1/temp' # Roseapple Pi, probably OrangePi's: https://dietpi.com/phpbb/viewtopic.php?t=8677
      '/sys/class/hwmon/hwmon[0-9]/temp[1-9]_input'
    )

    # Coders NB: Do NOT quote the array to allow coretemp file paths glob expansion!
    # shellcheck disable=SC2068
    for i in "${afp_temperature[@]}"; do
      [[ -f $i ]] || continue
      read -r temp < "$i"
      [[ $temp -gt 0 ]] && break # Trust only positive temperatures for now (strings are treated as "0")
    done
  fi

  # Format output
  # - Check for valid value: We must always return a value, due to VM lacking this feature + benchmark online
  if [[ $temp -lt 1 ]]; then
    echo 'N/A'
  else
    # 2/5 digit output?
    ((temp >= 200)) && temp=$((temp / 1000))

    if [[ $print_full_info != 1 ]]; then
      echo "$temp"
    else
      local temp_f=$((temp * 9 / 5 + 32))
      if ((temp >= 70)); then
        printf "%b\n" "\e[1;31mWARNING: $temp °C / $temp_f °F : Reducing the life of your device\e[0m"

      elif ((temp >= 60)); then
        printf "%b\n" "\e[38;5;202m$temp °C / $temp_f °F \e[90m: Running hot, not recommended\e[0m"

      elif ((temp >= 50)); then
        printf "%b\n" "\e[1;33m$temp °C / $temp_f °F \e[90m: Running warm, but safe\e[0m"

      elif ((temp >= 40)); then
        printf "%b\n" "\e[1;32m$temp °C / $temp_f °F \e[90m: Optimal temperature\e[0m"

      elif ((temp >= 30)); then
        printf "%b\n" "\e[1;36m$temp °C / $temp_f °F \e[90m: Cool runnings\e[0m"
      else
        printf "%b\n" "\e[1;36m$temp °C / $temp_f °F \e[90m: Who put me in the freezer!\e[0m"
      fi
    fi
  fi
}

# Returns current CPU usage in %
G_OBTAIN_CPU_USAGE(){

  local usage=0

  # ps: inaccurate but fast
  while read -r line; do   # Aside reading raw, -r removes leading and trailing white spaces each line
    line=${line/./}        # Remove decimal dot
    ((usage += ${line#0})) # Remove leading zero, if present, then sum up

  done < <(ps --no-headers -eo %cpu) # Single core usage in xy.z

  # ps returns single core usage, so we divide by core count
  usage=$(printf '%.1f' "$((usage * 10 / G_HW_CPU_CORES + 1))e-2") # Divide by 10 to compensate decimal dot removal, re-add decimal dot via printf conversion but assure last digit is rounded correctly

  echo "$usage"

}
