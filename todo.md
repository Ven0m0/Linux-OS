Install packages from list
```bash
mapfile -t arr < <(grep -v '^\s*#' file.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
printf '%s\n' "${arr[@]}" | paru -Sq --noconfirm
```

**Bash**
- https://github.com/sharkdp/config-files
- https://github.com/Naheel-Azawy/fmz
- https://www.commandlinefu.com/commands/browse
- [Shell-ng](https://github.com/joknarf/shell-ng)


```
https://github.com/lbarchive/yjl
https://github.com/procount/pinn
https://github.com/SixArm/unix-shell-script-tactics
https://github.com/ayumu436/arch-linux-scripts
https://github.com/klaver/sysctl/blob/master/sysctl.conf
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
https://rust.libhunt.com/categories
https://apps.kde.org
https://dash.cloudflare.com
```
