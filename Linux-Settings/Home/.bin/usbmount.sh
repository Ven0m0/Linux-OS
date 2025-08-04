#!/usr/bin/env bash
# Mounting or Unmounting devices via the terminal
# This script requires that you have installed and that you have rights.
# Create an executable file /usr/local/bin/usbstick.sh:

# Set the number of USB port available
usbCount=4
# ^ You have to create as many directories as USB port available
#   ( e.g. run the commands 'mkdir /mnt/usbstick1'
#   to 'mkdir /mnt/usbstick4' prior to running this script )

# Search for new devices starting by /dev/sdX with X the value of
deviceStart="b" #/dev/sdb
# ^ To list only new devices, you have to jump over the ones
#   already set. If you have 1 main drive (/dev/sda), start with
#   "b" (/dev/sdb) as value for this variable

# Search for new device(s)
lsblk -no NAME,UUID,FSTYPE,LABEL,MOUNTPOINT | grep -e "sd[$deviceStart-z][0-9]" > /tmp/usbstick
deviceCount=$(cat /tmp/usbstick | wc -l)

if [ $deviceCount -eq 0 ]
then
    echo "No new device detected"
    exit 0
fi

echo "Mount/Umount tool"

# Display new device(s) and read user input
i=0
while read -r name uuid fstype label
    do i=$(($i+1));
    echo "    $i)    $uuid $fstype [$label]"
done < /tmp/usbstick
echo "    q)    quit"

read -p "Choose the drive to be mount/umount : " input

if [[ "$input" == "Q" || "$input" == "q" ]]
then
    echo "    ---> Exiting"
    exit 0
fi

if [[ $input -ge 1 && $input -le $deviceCount ]]
then
    # Get the device selected by the user
    i=0
    while read -r name uuid fstype label
        do i=$(($i+1));
        [ $i -eq $input ] && break
    done < /tmp/usbstick

    # Check if the device is already mounted
    mountpoint=$(echo $label | grep -o "/mnt/usbstick[1-$usbCount]")

    if [ -z $mountpoint ]
    then
        # Search for the next "mount" directory available
        i=0
        while [ $i -le $usbCount ]
            do i=$(($i+1));
            mountpoint=$(cat /tmp/usbstick | grep -o "/mnt/usbstick$i")
            [ -z $mountpoint ] && break
        done

        if [ $i -gt $usbCount ]
        then
            echo "    ---> Set a higher number of USB port available"
            exit 1
        fi

        # Mount the device
        mount -o gid=users,fmask=113,dmask=002 -U $uuid /mnt/usbstick$i
        echo "    ---> Device $uuid mounted as /mnt/usbstick$i"
    else
        # Unmount the device
        umount $mountpoint
        echo "    ---> Device $uuid unmounted [$mountpoint]"
    fi
    exit 0
else
    echo "    ---> Invalid menu choice"
    exit 1
fi
