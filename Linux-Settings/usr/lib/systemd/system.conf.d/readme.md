https://github.com/lutris/docs/blob/master/HowToEsync.md

sudo nano /usr/lib/systemd/system.conf.d/limits.conf 
[Manager]
DefaultLimitNOFILE=524288
DumpCore=no

sudo nano /usr/lib/systemd/user.conf.d/limits.conf
[Manager]
DefaultLimitNOFILE=524288
DumpCore=no
