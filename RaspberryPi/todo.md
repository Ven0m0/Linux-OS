https://github.com/Rudxain/dotfiles

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
 "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
 $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
 sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-proposed-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ trixie-backports main contrib non-free non-free-firmware
```
```bash
apt-get -Uqy full-upgrade

```


apt-gc

```sh
#!/bin/sh
set -f
# garbage-collect

if [ "_$1" = _--deep ]; then
	apt-get -y clean
	apt -y purge ?config-files
	apt-mark -y minimize-manual
	apt-get -y autopurge
else
	apt-get autoclean
	apt-get autoremove
	apt purge ?config-files
fi
```

### [Nala] (https://github.com/volitank/nala)

```bash
sudo apt-get -y install nala
```

- https://github.com/pacstall/pacstall
- https://github.com/wimpysworld/deb-get

### Rust

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --default-toolchain nightly
```

```bash
sudo apt install rustup
```

### Lists

https://firebog.net/

https://github.com/framps/raspberryTools.git

https://github.com/novaspirit/rpi_zram
