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
