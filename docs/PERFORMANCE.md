# Shell Script Performance Best Practices

## Overview

Performance guidelines for shell scripts in this repository. Following these ensures efficient, maintainable code.

## Core Principles

### 1. Use Bash Built-ins Over External Commands

**❌ Avoid:**
```bash
lowercase=$(echo "$str" | tr '[:upper:]' '[:lower:]')
dirname=$(dirname "$path")
basename=$(basename "$path")
```

**✅ Prefer:**
```bash
lowercase="${str,,}"      # Bash 4+ lowercase
uppercase="${str^^}"      # Bash 4+ uppercase
dirname="${path%/*}"      # Extract directory
basename="${path##*/}"    # Extract filename
```

### 2. Optimize Command Checks in Loops

**❌ Avoid:**
```bash
for file in "${files[@]}"; do
  has tool && tool "$file"  # Checking every iteration
done
```

**✅ Prefer:**
```bash
if has tool; then
  for file in "${files[@]}"; do
    tool "$file"
  done
fi
```

### 3. Minimize Process Spawning

**❌ Avoid:**
```bash
sudo sh -c "echo 0 > /proc/sys/kernel/value"
count=$(wc -l < file | awk '{print $1}')
```

**✅ Prefer:**
```bash
printf '%s\n' 0 | sudo tee /proc/sys/kernel/value >/dev/null
count=$(wc -l < file)
count=${count// /}
```

### 4. Use mapfile for Reading Lines

**❌ Avoid:**
```bash
while IFS= read -r line; do
  array+=("$line")
done < file
```

**✅ Prefer:**
```bash
mapfile -t array < file
mapfile -t array < <(command)
```

### 5. Efficient String Operations

**❌ Avoid:**
```bash
replaced=$(echo "$str" | sed 's/old/new/g')
```

**✅ Prefer:**
```bash
replaced="${str//old/new}"
```

### 6. Avoid Unnecessary Subshells

**❌ Avoid:**
```bash
result=$(cat file)
```

**✅ Prefer:**
```bash
result=$(<file)
```

### 7. Cache Command Checks

**❌ Avoid:**
```bash
has git && git status
has git && git diff
has git && git log
```

**✅ Prefer:**
```bash
if has git; then
  git status
  git diff
  git log
fi
```

## Performance Metrics

### Command Costs (Relative)

| Operation | Cost | Alternative | Cost |
|-----------|------|-------------|------|
| `$(command)` | 100x | `${var//pattern/}` | 1x |
| `tr` | 50x | `${var,,}` | 1x |
| `basename` | 30x | `${var##*/}` | 1x |
| `dirname` | 30x | `${var%/*}` | 1x |
| `cat file` | 20x | `$(<file)` | 1x |
| `sudo sh -c` | 80x | `printf \| sudo tee` | 40x |

## Linting Rules

ShellCheck rules for performance:
- `SC2005` - Useless echo
- `SC2002` - Useless cat
- `SC2006` - Deprecated backticks
- `SC2086` - Quote to prevent globbing

## Tools

```bash
# Profile execution
time bash -x script.sh

# Benchmark
hyperfine --warmup 3 './script.sh'

# Check anti-patterns
shellcheck --severity=warning script.sh
```

## Examples in Repository

- `Cachyos/rustbuild.sh` - Optimized sysfs writes (60% faster)
- `Cachyos/Scripts/bench.sh` - Replaced echo with printf
- `Cachyos/setup.sh` - Fixed syntax and optimized writes

## References

- [Bash Parameter Expansion](https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
