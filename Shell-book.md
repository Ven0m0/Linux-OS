<details>
<summary><b>Bash Package Managers</b></summary>

- [Basher](https://www.basher.it/package)
- [bpkg](https://bpkg.sh)

</details>
<details>
<summary><b>Resources</b></summary>
  
* [Pure-bash-bible](https://github.com/dylanaraps/pure-bash-bible)

- [Pure-sh-bible](https://github.com/dylanaraps/pure-sh-bible)

- [Bash Guide](https://guide.bash.academy) &nbsp; [Bash Guide old](https://mywiki.wooledge.org/BashGuide)

- [Google's shellguide](https://google.github.io/styleguide/shellguide.html)

- [Bash optimizations](https://www.reddit.com/r/bash/comments/1ky4r7l/stop_writing_slow_bash_scripts_performance)

- [Ascii flag color codes](https://www.flagcolorcodes.com)

- [Bash prompt generator](https://bash-prompt-generator.org) &nbsp;&nbsp; [Ezprompt generator](https://ezprompt.net)

</details>

## Bash snippets

<details>
<summary><b>Script start template</b></summary>

```bash
#!/usr/bin/env bash -euo pipefail
shopt -s nullglob globstar; IFS=$'\n\t' SHELL="$(command -v bash 2>/dev/null)"
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
builtin cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD" || exit 1
[[ $EUID -ne 0 ]] && sudo -v
sync; sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' &>/dev/null
#──────────── Color & Effects ────────────
BLK=$'\e[30m' WHT=$'\e[37m' BWHT=$'\e[97m'
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
BLU=$'\e[34m' CYN=$'\e[36m' LBLU=$'\e[38;5;117m'
MGN=$'\e[35m' PNK=$'\e[38;5;218m'
DEF=$'\e[0m' BLD=$'\e[1m'
#──────────── Helpers ────────────────────
# Check for command
has(){ command -v "$1" &>/dev/null; }
# Get basename of command if on path
hasname(){ local x; x=$(type -Pf -- "$1") && printf '%s\n' "${x##*/}"; }
# Export array of newline/space seperated quotes variables
export_array(){ local -n a=$1; for v in "${a[@]}"; do eval "export $v"; done; unset v; }
# Printf-echo
p(){ printf '%s\n' "$*" 2>/dev/null; }
# Printf-echo for color with auto reset
pe(){ printf '%b\n' "$*"$'\e[0m' 2>/dev/null; }
# Bash sleep replacement
sleepy(){ read -rt "${1:-1}" -- <> <(:) &>/dev/null || :; }
#─────────────────────────────────────────────────────────────
```

</details>
<details>
<summary><b>Ascii color table</b></summary>

```bash
#──────────── Effects ────────────
DEF=$'\e[0m'   BLD=$'\e[1m'   DIM=$'\e[2m'
UND=$'\e[4m'   INV=$'\e[7m'   HID=$'\e[8m'
#──────────── Standard Colors ────────────
BLK=$'\e[30m'  RED=$'\e[31m'  GRN=$'\e[32m'
YLW=$'\e[33m'  BLU=$'\e[34m'  MGN=$'\e[35m'
CYN=$'\e[36m'  WHT=$'\e[37m'  PNK=$'\e[38;5;205m'
#──────────── Bright Colors ──────────────
BBLK=$'\e[90m' BRED=$'\e[91m' BGRN=$'\e[92m'
BYLW=$'\e[93m' BBLU=$'\e[94m' BMGN=$'\e[95m'
BCYN=$'\e[96m' BWHT=$'\e[97m'
#──────────── Backgrounds ────────────────
BG_BLK=$'\e[40m'  BG_RED=$'\e[41m'  BG_GRN=$'\e[42m'
BG_YLW=$'\e[43m'  BG_BLU=$'\e[44m'  BG_MGN=$'\e[45m'
BG_CYN=$'\e[46m'  BG_WHT=$'\e[47m'
#──────────── Bright Backgrounds ─────────
BG_BBLK=$'\e[100m' BG_BRED=$'\e[101m' BG_BGRN=$'\e[102m'
BG_BYLW=$'\e[103m' BG_BBLU=$'\e[104m'
BG_BMGN=$'\e[105m' BG_BCYN=$'\e[106m' BG_BWHT=$'\e[107m'
#──────────── 256 Color (Functions) ──────
FG256(){ printf $'\e[38;5;%sm' "$1"; }
BG256(){ printf $'\e[48;5;%sm' "$1"; }
#──────────── Truecolor (24-bit RGB) ─────
FGRGB(){ printf $'\e[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
BGRGB(){ printf $'\e[48;2;%s;%s;%sm' "$1" "$2" "$3"; }
#─────────────────────────────────────────
```

</details>
<details>
<summary><b>Basename</b></summary>

Usage: basename "path" ["suffix"]

```bash
bname(){ local t=${1%${1##*[!/}]}; t=${t##*/}; [[ $2 && $t == *"$2" ]] && t=${t%$2}; printf '%s\n' "${t:-/}"; }
```

</details>
<details>
<summary><b>Dirname</b></summary>

Usage: dirname "path"

```bash
dname(){ local p=${1:-.}; [[ $p != *[!/]* ]] && { printf '/\n'; return; }; p=${p%${p##*[!/]}}; [[ $p != */* ]] && { printf '.\n'; return; }; p=${p%/*}; p=${p%${p##*[!/]}}; printf '%s\n' "${p:-/}"; }
```

</details>
<details>
<summary><b>Date</b></summary>

Usage: date "format"

Prints either current date 'day/month-hour-minute' or whatever you give it via 'date <arg>'

See: 'man strftime' for format.

```bash
date(){ local x="${1:-%d/%m/%y-%R}"; printf "%($x)T\n" '-1'; }
```

</details>
<details>
<summary><b>Faster cat</b></summary>

Hyperfine Summary:

```bash
$ hyperfine -w 5 -S bash -i "cat /etc/hostname" 'printf '%s\n' "$(</etc/hostname)"'

Benchmark 1: cat /etc/hostname
  Time (mean ± σ):       1.1 ms ±   0.0 ms    [User: 0.8 ms, System: 0.5 ms]
  Range (min … max):     1.1 ms …   1.2 ms    1057 runs
Benchmark 2: printf '%s\n' CachyOS
  Time (mean ± σ):      17.5 µs ±  20.2 µs    [User: 239.0 µs, System: 232.0 µs]
  Range (min … max):     0.0 µs … 233.7 µs    1729 runs
Summary
  printf '%s\n' CachyOS ran
   64.36 ± 74.11 times faster than cat /etc/hostname
```

```bash
fcat(){ printf '%s\n' "$(<${1})"; }
```

</details>
<details>
<summary><b>Sleep replacement in bash</b></summary>

```bash
#sleepy(){ read -rt "$1" <> <(:) &>/dev/null || :; }
```

</details>
<details>
<summary><b>Use regex on a string</b></summary>

```bash
regex(){ [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}" }
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
regex(){
    # Usage: regex "string" "regex"
    [[ $1 =~ $2 ]] && printf '%s\n' "${BASH_REMATCH[1]}"
}
```

</details>
<details>
<summary><b>Split a string on a delimiter</b></summary>

This is an alternative to `cut`, `awk` and other tools. **CAVEAT:** Requires `bash` 4+

```bash
split(){ IFS=$'\n' read -d "" -ra arr <<< "${1//$2/$'\n'}"; printf '%s\n' "${arr[@]}" }
```

**Example Function:**

```bash
split(){
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
trim_quotes(){
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
strip_all(){
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
strip(){
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

[Source](https://github.com/dylanaraps/pure-bash-bible?tab=readme-ov-file#remove-duplicate-array-elements)

Create a temporary associative array. When setting associative array
values and a duplicate assignment occurs, bash overwrites the key. This
allows us to effectively remove array duplicates.

**CAVEAT:** Requires `bash` 4+

**CAVEAT:** List order may not stay the same.

**Example Function:**

```bash
remove_array_dups(){
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
extract(){
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

````shell
# Extract code blocks from MarkDown file.
$ extract ~/projects/pure-bash/README.md '```sh' '```'
# Output here...
````

</details>
<details>
<summary><b>Variables</b></summary>

### Indirection

| Parameter  | What does it do?                                                                                                                       |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `${!VAR}`  | Access a variable based on the value of `VAR`.                                                                                         |
| `${!VAR*}` | Expand to `IFS` separated list of variable names starting with `VAR`.                                                                  |
| `${!VAR@}` | Expand to `IFS` separated list of variable names starting with `VAR`. If double-quoted, each variable name expands to a separate word. |

### Replacement

| Parameter                 | What does it do?                                       |
| ------------------------- | ------------------------------------------------------ |
| `${VAR#PATTERN}`          | Remove shortest match of pattern from start of string. |
| `${VAR##PATTERN}`         | Remove longest match of pattern from start of string.  |
| `${VAR%PATTERN}`          | Remove shortest match of pattern from end of string.   |
| `${VAR%%PATTERN}`         | Remove longest match of pattern from end of string.    |
| `${VAR/PATTERN/REPLACE}`  | Replace first match with string.                       |
| `${VAR//PATTERN/REPLACE}` | Replace all matches with string.                       |
| `${VAR/PATTERN}`          | Remove first match.                                    |
| `${VAR//PATTERN}`         | Remove all matches.                                    |

### Length

| Parameter    | What does it do?             |
| ------------ | ---------------------------- |
| `${#VAR}`    | Length of var in characters. |
| `${#ARR[@]}` | Length of array in elements. |

### Expansion

| Parameter               | What does it do?                                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------- |
| `${VAR:OFFSET}`         | Remove first `N` chars from variable.                                                                                |
| `${VAR:OFFSET:LENGTH}`  | Get substring from `N` character to `N` character. <br> (`${VAR:10:10}`: Get sub-string from char `10` to char `20`) |
| `${VAR:: OFFSET}`       | Get first `N` chars from variable.                                                                                   |
| `${VAR:: -OFFSET}`      | Remove last `N` chars from variable.                                                                                 |
| `${VAR: -OFFSET}`       | Get last `N` chars from variable.                                                                                    |
| `${VAR:OFFSET:-OFFSET}` | Cut first `N` chars and last `N` chars.                                                                              | `bash 4.2+` |

### Case Modification

| Parameter  | What does it do?                 | CAVEAT    |
| ---------- | -------------------------------- | --------- |
| `${VAR^}`  | Uppercase first character.       | `bash 4+` |
| `${VAR^^}` | Uppercase all characters.        | `bash 4+` |
| `${VAR,}`  | Lowercase first character.       | `bash 4+` |
| `${VAR,,}` | Lowercase all characters.        | `bash 4+` |
| `${VAR~}`  | Reverse case of first character. | `bash 4+` |
| `${VAR~~}` | Reverse case of all characters.  | `bash 4+` |

### Default Value

| Parameter        | What does it do?                                                |
| ---------------- | --------------------------------------------------------------- |
| `${VAR:-STRING}` | If `VAR` is empty or unset, use `STRING` as its value.          |
| `${VAR-STRING}`  | If `VAR` is unset, use `STRING` as its value.                   |
| `${VAR:=STRING}` | If `VAR` is empty or unset, set the value of `VAR` to `STRING`. |
| `${VAR=STRING}`  | If `VAR` is unset, set the value of `VAR` to `STRING`.          |
| `${VAR:+STRING}` | If `VAR` is not empty, use `STRING` as its value.               |
| `${VAR+STRING}`  | If `VAR` is set, use `STRING` as its value.                     |
| `${VAR:?STRING}` | Display an error if empty or unset.                             |
| `${VAR?STRING}`  | Display an error if unset.                                      |

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

**Misc**

```bash
# Clear screen on script exit.
trap 'printf \\e[2J\\e[H\\e[m' EXIT

# Echo pwd, but replace HOME with ~
echo "${PWD/#$HOME/\~}"

# $HOME to ~
file="${1/#$HOME/\~}"
# ~ to ${HOME}
file="${1/#\~\//${HOME}/}"
```

**Run a command in the background**

This will run the given command and keep it running, even after the terminal or SSH connection is terminated. All output is ignored.

```bash
bkr(){
    (nohup "$@" &>/dev/null &)
}

bkr ./some_script.sh # some_script.sh is now running in the background
```

### alternative clear / fix scrollback buffer clear for kitty

```bash
printf '\e[3J\e[H\e[2J\e[m'
alias clear

alias clear "printf '\e[3J\e[H\e[2J\e[m'"
```
