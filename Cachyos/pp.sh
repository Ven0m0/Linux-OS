#!/bin/bash

sudo -v

arch=$(uname -m)
maxMirrorForDownload=4
pacmanCacheDir="$(pacman-conf CacheDir)"

if [[ $UID -ne 0 ]]; then
	sudo -p 'Restarting as root, password: ' bash $0 "$@"
	exit $?
fi

subprocessName="pacman"
subprocessArgument=()
while [ "$1" != "" ]; do
	case $1 in
		-a | --aur)
			shift
			subprocessName="$1"
			;;
		*)
			subprocessArgument+=("$1")
			;;
	esac
	shift
done

#read mirrorlist, "Server =" lines, remove all before and including "= " (10 char)
readarray -t mirrorArray < <(grep "^Server =" /etc/pacman.d/mirrorlist | cut -c 10-)

mirrorArrayLen=${#mirrorArray[@]}
let maxParallelDownload=$mirrorArrayLen/$maxMirrorForDownload

#randomize the order of the mirror
mirrorArray=( $(shuf -e "${mirrorArray[@]}") )

echo ">>> $(date +%T) | Checking for updates"
#now get the list of stuff to update
readarray -t packageList < <(checkupdates | cut -d ' ' -f 1,4)

echo ">>> $(date +%T) | Found ${#packageList[@]} updates"
echo ">>> $(date +%T) | Starting downloads using mirrorsNumber:$mirrorArrayLen maxParallelDownload:$maxParallelDownload maxMirrorForDownload:$maxMirrorForDownload"
pidToWait=()
declare -A pidToString
#pidToWaitStr=""
mirrorIndex=0
for pkgNameAndVersion in "${packageList[@]}"; do
	pkgName=${pkgNameAndVersion% *}
	
	repoAndArch=($(pacman -Si $pkgName | grep 'Repository      :\|Architecture    :' | cut -c 19-))
	
	repo=${repoAndArch[0]}
	archpkg=${repoAndArch[1]}
	
	downloadList=''
	for (( i=0; i<$maxMirrorForDownload; i++ )); do
		mirror=${mirrorArray[mirrorIndex]}
		pkgNameAndVersion=${pkgNameAndVersion/ /-}
		val=${mirror/\$repo/$repo}
		val=$(echo ${val/\$arch/$arch}/$pkgNameAndVersion-$archpkg.pkg.tar.zst)
		downloadList="$downloadList $val"
		((mirrorIndex++))
		if [[ $mirrorIndex -ge $mirrorArrayLen ]]; then
			mirrorIndex=0
		fi
	done
	
	aria2c -c $downloadList --connect-timeout=1 -s $maxMirrorForDownload -t 1 -d "$pacmanCacheDir" &> /dev/null &
	pidTmp=($!)
	pidToWait+=($pidTmp)
	pidToString[$pidTmp]=$pkgName
	pidToWaitStr+=" $pidTmp"
	
	running=$(jobs |wc -l)
	echo ">>> $(date +%T) | Downloading $pkgName, running/max download:$running/$maxParallelDownload"
	
	while [ $running -ge $maxParallelDownload ]; do
		sleep 0.1 #sleep 0.1 second
		running=$(jobs |wc -l)
	done
done

#now wait for all remaining jobs
echo ">>> $(date +%T) | All download started, waiting for completition"

for pid in "${pidToWait[@]}"; do
	printf "waiting for ${pidToString[$pid]} "
	wait $pid
	echo " completed"
done

echo ">>> $(date +%T) | All download complete"

echo ">>> $(date +%T) | Calling $subprocessName with arguments ${subprocessArgument[@]}"
if [[ $subprocessName != "pacman" ]]; then
	echo ">>> $(date +%T) | AUR helper detected, dropping privileges"
	#DROP PRIVILEDGES TO AVOID ISSUES
	sudo -s -u $SUDO_USER $subprocessName ${subprocessArgument[@]}
else
	$subprocessName ${subprocessArgument[@]}
fi

echo ">>> $(date +%T) | All done, bye"
