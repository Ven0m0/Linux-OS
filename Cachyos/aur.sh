

# Add key
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

# Add repo (Arch x86_64 only)
echo '
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
' | sudo tee -a /etc/pacman.conf

# Install mirrorlist
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
               'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

sudo pacman -Sy

