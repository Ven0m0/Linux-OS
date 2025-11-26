<https://github.com/OliPelz/utility-scripts.git>

### v2

```bash
strip_comments_and_white_spaces(){ sed -E -e 's/^\s+//' -e 's/\s+$//' -e '/^#.*$/d' -e '/^\s*$/d'; }
trim_white_spaces(){ sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }
use_minimal_function_header(){ sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z0-9_]+)[[:space:]]*\{/\1 () {/'; }
pp_strip_copyright(){ awk '!/^#/ {p=1} p'; }
pp_strip_separators(){ awk '!/^#[[:space:]]*[-─]{5,}/'; }
```
