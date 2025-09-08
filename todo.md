**Bash**

- https://github.com/sharkdp/config-files

- https://github.com/Naheel-Azawy/fmz

- [Shell-ng](https://github.com/joknarf/shell-ng)

  ```bash
  mkdir -p "${HOME}/local/share/shell-ng" && LC_ALL=C git clone --depth 1 --single-branch --filter=blob:none https://github.com/joknarf/shell-ng.git "${HOME}/local/share/shell-ng"
  ```

**Ascii color bash**
```
https://github.com/elenapan/dotfiles/blob/master/bin/bunnyfetch
https://github.com/aristocratos/bashtop
https://github.com/lbarchive/yjl
https://github.com/betafcc/clc
https://github.com/addy-dclxvi/almighty-dotfiles/blob/master/.toys/memefetch
https://github.com/procount/pinn
https://github.com/SixArm/unix-shell-script-tactics
https://github.com/ayumu436/arch-linux-scripts
https://github.com/Hmz-x/std-references/blob/master/sh.txt
https://github.com/Hmz-x/std-references/blob/master/bash.txt
https://github.com/ptitfred/posix-toolbox/blob/main/src/short-path/short-path.sh
https://mrpicklepinosaur.github.io/shrs
https://github.com/klaver/sysctl/blob/master/sysctl.conf
https://github.com/rpotter12/dotfiles/blob/master/.bashrc
```

**Replace -O1/-O2 with -O3**
```bash
CFLAGS="${CFLAGS/-O1/-O3}" CFLAGS="${CFLAGS/-O2/-O3}"; export CFLAGS="$(printf '%s\n' "$CFLAGS" | xargs)"
CFLAGS="${CXXFLAGS/-O1/-O3}" CFLAGS="${CXXFLAGS/-O2/-O3}"; export CXXFLAGS="$(printf '%s\n' "$CXXFLAGS" | xargs)"
LDFLAGS="${LDFLAGS/-O1/-O3}" LDFLAGS="${LDFLAGS/-O2/-O3}"; export LDFLAGS="$(printf '%s\n' "$LDFLAGS" | xargs)"
```

**Append flags to the var (No dupes)**
```bash
append_unique_word(){
  local varname="$1" nw="$2" ow value; local -n cur=$varname
  for ow in $cur; do [[ $ow == "$nw" ]] && return 0; done
  value="${cur:+$cur }$nw"
  printf -v "$varname" %s "$value"; export "$varname"
}
append_unique_word CFLAGS "-O3"
append_unique_word CFLAGS "-pipe"
```

```markdown
https://shields.io
https://simpleicons.org
https://emojicombos.com/cat
https://www.asciiart.eu/text-to-ascii-art
https://manytools.org/hacker-tools/ascii-banner

https://dotfiles.github.io/tips
https://hub.docker.com/search?q
https://crates.io
https://rust.libhunt.com/categories
https://apps.kde.org
https://www.shellcheck.net
https://dash.cloudflare.com
```
