!#basb

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "add this to /etc/pacman.conf"
echo "[chaotic-aur]"
echo "Include = /etc/pacman.d/chaotic-mirrorlist"

echo "'sudo pacman -Syu' afterwards"
