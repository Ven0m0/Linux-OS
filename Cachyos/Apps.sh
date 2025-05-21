

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' && sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

sudo nano /etc/pacman.conf
[core-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist

[extra-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist

[artafinde]
Server = https://pkgbuild.com/~artafinde/repo

[kde-unstable]
Include = /etc/pacman.d/mirrorlist


NoExtract = usr/share/doc/*
NoExtract = /usr/share/help/*
NoExtract = /usr/share/gtk-doc/*
NoExtract = usr/share/locale/* usr/share/X11/locale/*/* usr/share/i18n/locales/* opt/google/chrome/locales/* !usr/share/X11/locale/C/* !usr/share/X11/locale/en_US.UTF-8/*
NoExtract = !usr/share/X11/locale/compose.dir !usr/share/X11/locale/iso8859-1/*
NoExtract = !*locale*/en*/* !usr/share/*locale*/locale.*
NoExtract = !usr/share/*locales/en_?? !usr/share/*locales/i18n* !usr/share/*locales/iso*
NoExtract = usr/share/i18n/charmaps/* !usr/share/i18n/charmaps/UTF-8.gz !usr/share/i18n/charmaps/ANSI_X3.4-1968.gz
NoExtract = !usr/share/*locales/trans*
NoExtract = !usr/share/*locales/C !usr/share/*locales/POSIX
NoExtract = usr/share/man/* !usr/share/man/man*
NoExtract = usr/share/vim/vim*/lang/*
NoExtract = usr/share/*/translations/*.qm !usr/share/*/translations/*en.qm usr/share/*/nls/*.qm usr/share/qt/phrasebooks/*.qph usr/share/qt/translations/*.pak !*/en-US.pak
NoExtract = usr/share/*/locales/*.pak opt/*/locales/*.pak usr/lib/*/locales/*.pak !*/en-US.pak
NoExtract = usr/lib/libreoffice/help/en-US/*
NoExtract = usr/share/ibus/dicts/emoji-*.dict !usr/share/ibus/dicts/emoji-en.dict

pacman -S bauh
