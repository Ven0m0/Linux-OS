https://github.com/Rudxain/dotfiles


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

### Lists

https://firebog.net/

https://github.com/framps/raspberryTools.git

https://github.com/novaspirit/rpi_zram
