

## Bash Package Managers

* [Basher](https://www.basher.it/package)
* [bpkg](https://bpkg.sh)


## Bash snippets

<details>
<summary><b>Script start template</b></summary>
  
```bash
#!/usr/bin/bash
set -eEuo pipefail; IFS=$'\n\t'; shopt -s nullglob globstar
shopt -s inherit_errexit 
export LC_COLLATE=C LC_CTYPE=C LANG=C.UTF-8
#──────────── Foreground colors ────────────
BLK='\033[30m' # Black
RED='\033[31m' # Red
GRN='\033[32m' # Green
YLW='\033[33m' # Yellow
BLU='\033[34m' # Blue
MGN='\033[35m' # Magenta
CYN='\033[36m' # Cyan
WHT='\033[37m' # White
#──────────── Effects ────────────
DEF='\033[0m'  # Reset to default
BLD='\033[1m'  # Bold / Bright
#──────────── Bright colors ────────────
BRIGHT_RED='\033[91m'
BRIGHT_GRN='\033[92m'
BRIGHT_YLW='\033[93m'
BRIGHT_BLU='\033[94m'
BRIGHT_MGN='\033[95m'
BRIGHT_CYN='\033[96m'
BRIGHT_WHT='\033[97m'
#────────────────────────
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $WORKDIR
```
</details>
<details>
<summary><b>Get external IP</b></summary>

```bash
curl -fsS ipinfo.io/ip || curl -fsS http://ipecho.net/plain
```
</details>
<details>
<summary><b>Sleep replacement in bash</b></summary>

```bash
#sleepy() { read -rt 0.1 <> <(:) &>/dev/null || :; }
```
</details>
<details>
<summary><b>Use regex on a string</b></summary>

```bash
regex() { [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}" }
```

The result of `bash`'s regex matching can be used to replace `sed` for a
large number of use-cases.

**CAVEAT**: This is one of the few platform dependent `bash` features.
`bash` will use whatever regex engine is installed on the user's system.
Stick to POSIX regex features if aiming for compatibility.

**CAVEAT**: This example only prints the first matching group. When using
multiple capture groups some modification is needed.

**Example Function:**

```bash
regex() {
    # Usage: regex "string" "regex"
    [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}
```
</details>
<details>
<summary><b>Split a string on a delimiter</b></summary>&nbsp;

&nbsp;
**CAVEAT:** Requires `bash` 4+

This is an alternative to `cut`, `awk` and other tools.

```bash
split() { IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"; printf '%s\n' "${arr[@]}" }
```

**Example Function:**

```bash
split() {
   # Usage: split "string" "delimiter"
   IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"
   printf '%s\n' "${arr[@]}"
}
```

**Example Usage:**

```shell
$ split "apples,oranges,pears,grapes" ","
apples
oranges
pears
grapes

$ split "1, 2, 3, 4, 5" ", "
1
2
3
4
5

# Multi char delimiters work too!
$ split "hello---world---my---name---is---john" "---"
hello
world
my
name
is
john
```
</details>
