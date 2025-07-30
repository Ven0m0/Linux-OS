

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
<summary><b>Split a string on a delimiter</b></summary>

This is an alternative to `cut`, `awk` and other tools. **CAVEAT:** Requires `bash` 4+

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
<details>
<summary><b>Trim quotes from a string</b></summary>

**Example Function:**

```bash
trim_quotes() {
    # Usage: trim_quotes "string"
    : "${1//\'}"
    printf '%s\n' "${_//\"}"
}
```

**Example Usage:**

```shell
$ var="'Hello', \"World\""
$ trim_quotes "$var"
Hello, World
```
</details>
<details>
<summary><b>Strip all instances of pattern from string</b></summary>

**Example Function:**

```sh
strip_all() {
    # Usage: strip_all "string" "pattern"
    printf '%s\n' "${1//$2}"
}
```

**Example Usage:**

```shell
$ strip_all "The Quick Brown Fox" "[aeiou]"
Th Qck Brwn Fx

$ strip_all "The Quick Brown Fox" "[[:space:]]"
TheQuickBrownFox

$ strip_all "The Quick Brown Fox" "Quick "
The Brown Fox
```
</details>
<details>
<summary><b>Strip first occurrence of pattern from string</b></summary>

**Example Function:**

```bash
strip() {
    # Usage: strip "string" "pattern"
    printf '%s\n' "${1/$2}"
}
```

**Example Usage:**

```shell
$ strip "The Quick Brown Fox" "[aeiou]"
Th Quick Brown Fox

$ strip "The Quick Brown Fox" "[[:space:]]"
TheQuick Brown Fox
```
</details>
<details>
<summary><b>Remove duplicate array elements</b></summary>&nbsp;

Create a temporary associative array. When setting associative array
values and a duplicate assignment occurs, bash overwrites the key. This
allows us to effectively remove array duplicates.

**CAVEAT:** Requires `bash` 4+

**CAVEAT:** List order may not stay the same.

**Example Function:**

```bash
remove_array_dups() {
    # Usage: remove_array_dups "array"
    declare -A tmp_array

    for i in "$@"; do
        [[ $i ]] && IFS=" " tmp_array["${i:- }"]=1
    done

    printf '%s\n' "${!tmp_array[@]}"
}
```

**Example Usage:**

```shell
$ remove_array_dups 1 1 2 2 3 3 3 3 3 4 4 4 4 4 5 5 5 5 5 5
1
2
3
4
5

$ arr=(red red green blue blue)
$ remove_array_dups "${arr[@]}"
red
green
blue
```
</details>
<details>
<summary><b>Loop over the contents of a file</b></summary>

```shell
while read -r line; do
    printf '%s\n' "$line"
done < "file"
```

</details>
<details>
<summary><b>## Loop over files and directories</b></summary>

Don’t use `ls`.

```shell
# Greedy example.
for file in *; do
    printf '%s\n' "$file"
done

# PNG files in dir.
for file in ~/Pictures/*.png; do
    printf '%s\n' "$file"
done

# Iterate over directories.
for dir in ~/Downloads/*/; do
    printf '%s\n' "$dir"
done

# Brace Expansion.
for file in /path/to/parentdir/{file1,file2,subdir/file3}; do
    printf '%s\n' "$file"
done

# Iterate recursively.
shopt -s globstar
for file in ~/Pictures/**/*; do
    printf '%s\n' "$file"
done
shopt -u globstar
```
</details>
