https://github.com/shellspec/shellbench

https://github.com/Zuzzuc/Bash-minifier

https://github.com/OliPelz/utility-scripts.git


[shtext](https://github.com/pforret/shtext)
```bash
basher install pforret/shtext
```
```bash
git clone https://github.com/pforret/shtext.git && cd shtext && chmod +x shtext.sh
```

### v2:
```bash
function strip_comments_and_white_spaces {
	sed -E -e 's/^\s+//' -e 's/\s+$//' -e '/^#.*$/d' -e '/^\s*$/d'
}
trim_white_spaces() {
    sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}
use_minimal_function_header() {
    sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\{/\1 () {/'
}
```

### v1:
```bash
pp_strip_comments() {
	sed '/^[[:space:]]*#.*$/d'
}
pp_strip_copyright() {
    awk '!/^#/ {p=1} p'
}
pp_strip_separators() {
    awk '!/^#[[:space:]]*-{5,}/'
}
```
