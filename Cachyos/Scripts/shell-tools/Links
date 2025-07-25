https://github.com/shellspec/shellbench

https://github.com/Zuzzuc/Bash-minifier
https://github.com/OliPelz/utility-scripts.git


### v2:
```bash
function strip_comments_and_white_spaces {
	sed -E -e 's/^\s+//' -e 's/\s+$//' -e '/^#.*$/d' -e '/^\s*$/d'
}
function trim_white_spaces {
	sed -E -e 's/^\s+//' -e 's/\s+$//'
}
function use_minimal_function_header {
	sed -E 's/function ([a-zA-Z0-9_]*) \{/\1 () {/'
}
```

### v1:
```bash
pp_strip_comments() {
	sed '/^[[:space:]]*#.*$/d'
}
pp_strip_copyright() {
	awk '/^#/ {if(!p){ next }} { p=1; print $0 }'
}
pp_strip_separators() {
	awk '/^#\s*-{5,}/ { next; } {print $0}'
}
```
