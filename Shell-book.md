

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
#──────────── Color & Effects ────────────
BLK='\e[30m' # Black
RED='\e[31m' # Red
GRN='\e[32m' # Green
YLW='\e[33m' # Yellow
BLU='\e[34m' # Blue
MGN='\e[35m' # Magenta
CYN='\e[36m' # Cyan
WHT='\e[37m' # White
DEF='\e[0m'  # Reset to default
BLD='\e[1m'  #Bold
#─────────────────────────────────────────
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

### [Pure-bash-bible](https://github.com/dylanaraps/pure-bash-bible)

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
<summary><b>Loop over files and directories</b></summary>

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
<details>
<summary><b>Extract lines between two markers</b></summary>

**Example Function:**

```bash
extract() {
    # Usage: extract file "opening marker" "closing marker"
    while IFS=$'\n' read -r line; do
        [[ $extract && $line != "$3" ]] &&
            printf '%s\n' "$line"

        [[ $line == "$2" ]] && extract=1
        [[ $line == "$3" ]] && extract=
    done < "$1"
}
```

**Example Usage:**

```shell
# Extract code blocks from MarkDown file.
$ extract ~/projects/pure-bash/README.md '```sh' '```'
# Output here...
```
</details>
<details>
<summary><b>Variables</b></summary>

### Indirection

| Parameter | What does it do? |
| --------- | ---------------- |
| `${!VAR}` | Access a variable based on the value of `VAR`.
| `${!VAR*}` | Expand to `IFS` separated list of variable names starting with `VAR`. |
| `${!VAR@}` | Expand to `IFS` separated list of variable names starting with `VAR`. If double-quoted, each variable name expands to a separate word. |


### Replacement

| Parameter | What does it do? |
| --------- | ---------------- |
| `${VAR#PATTERN}` | Remove shortest match of pattern from start of string. |
| `${VAR##PATTERN}` | Remove longest match of pattern from start of string. |
| `${VAR%PATTERN}` | Remove shortest match of pattern from end of string. |
| `${VAR%%PATTERN}` | Remove longest match of pattern from end of string. |
| `${VAR/PATTERN/REPLACE}` | Replace first match with string.
| `${VAR//PATTERN/REPLACE}` | Replace all matches with string.
| `${VAR/PATTERN}` | Remove first match.
| `${VAR//PATTERN}` | Remove all matches.

### Length

| Parameter | What does it do? |
| --------- | ---------------- |
| `${#VAR}` | Length of var in characters.
| `${#ARR[@]}` | Length of array in elements.

### Expansion

| Parameter | What does it do? |
| --------- | ---------------- |
| `${VAR:OFFSET}` | Remove first `N` chars from variable.
| `${VAR:OFFSET:LENGTH}` | Get substring from `N` character to `N` character. <br> (`${VAR:10:10}`: Get sub-string from char `10` to char `20`)
| `${VAR:: OFFSET}` | Get first `N` chars from variable.
| `${VAR:: -OFFSET}` | Remove last `N` chars from variable.
| `${VAR: -OFFSET}` | Get last `N` chars from variable.
| `${VAR:OFFSET:-OFFSET}` | Cut first `N` chars and last `N` chars. | `bash 4.2+` |

### Case Modification

| Parameter | What does it do? | CAVEAT |
| --------- | ---------------- | ------ |
| `${VAR^}` | Uppercase first character. | `bash 4+` |
| `${VAR^^}` | Uppercase all characters. | `bash 4+` |
| `${VAR,}` | Lowercase first character. | `bash 4+` |
| `${VAR,,}` | Lowercase all characters. | `bash 4+` |
| `${VAR~}` | Reverse case of first character. | `bash 4+` |
| `${VAR~~}` | Reverse case of all characters. | `bash 4+` |

### Default Value

| Parameter | What does it do? |
| --------- | ---------------- |
| `${VAR:-STRING}` | If `VAR` is empty or unset, use `STRING` as its value.
| `${VAR-STRING}` | If `VAR` is unset, use `STRING` as its value.
| `${VAR:=STRING}` | If `VAR` is empty or unset, set the value of `VAR` to `STRING`.
| `${VAR=STRING}` | If `VAR` is unset, set the value of `VAR` to `STRING`.
| `${VAR:+STRING}` | If `VAR` is not empty, use `STRING` as its value.
| `${VAR+STRING}` | If `VAR` is set, use `STRING` as its value.
| `${VAR:?STRING}` | Display an error if empty or unset.
| `${VAR?STRING}` | Display an error if unset.


### BRACE EXPANSION

**Ranges**

```shell
# Syntax: {<START>..<END>}

# Print numbers 1-100.
echo {1..100}

# Print range of floats.
echo 1.{1..9}

# Print chars a-z.
echo {a..z}
echo {A..Z}

# Nesting.
echo {A..Z}{0..9}

# Print zero-padded numbers.
# CAVEAT: bash 4+
echo {01..100}

# Change increment amount.
# Syntax: {<START>..<END>..<INCREMENT>}
# CAVEAT: bash 4+
echo {1..10..2} # Increment by 2.
```

**String Lists**

```shell
echo {apples,oranges,pears,grapes}

# Example Usage:
# Remove dirs Movies, Music and ISOS from ~/Downloads/.
rm -rf ~/Downloads/{Movies,Music,ISOS}
```
</details>

### [Pure-sh-bible](https://github.com/dylanaraps/pure-sh-bible)
