# Security Rules

## Forbidden Constructs

- `eval` — NEVER. Use arrays: `local -a cmd=("$@"); "${cmd[@]}"`
- `bash -c "$var"` with unsanitized input — NEVER
- Backtick command substitution — NEVER (use `$(...)`)
- Parsing `ls` output — NEVER (use globs or `fd`)
- Predictable temp files — NEVER use `/tmp/script.$$`; use `mktemp`

## Input Validation (mandatory for all user-supplied values)

```bash
# Paths: only alphanumeric + / _ . -
[[ $path =~ ^[[:alnum:]/_.-]+$ ]] || die "invalid path: $path"
[[ ! $path =~ \.\. ]] || die "path traversal detected"

# Package names: only lowercase alphanumeric + @ . _ + -
[[ $pkg =~ ^[a-z0-9@._+-]+$ ]] || die "invalid package: $pkg"
```

## Temp File Security

```bash
# Required pattern
TMPFILE=$(mktemp) || die "mktemp failed"
chmod 600 "$TMPFILE"

# Atomic writes
printf '%s\n' "$content" > "${file}.tmp"
chmod 644 "${file}.tmp"
mv -f "${file}.tmp" "$file"
```

## Secrets — DO NOT READ OR WRITE

Never read, write, or cat these paths:
- `.gnupg/`, `.ssh/id_*`, `*.key`, `*.pem`, `*.credentials`, `*.secret`
- `.config/gh/hosts.yml` (GitHub tokens)
- Any file matching `*token*`, `*password*`, `*apikey*`

## Command Array Pattern (injection prevention)

```bash
# Correct — array expansion, no injection
local -a cmd=(pacman -S --noconfirm)
cmd+=("$pkg")
"${cmd[@]}"

# Forbidden — string concatenation passed to shell
pacman -S "$extra_flags $pkg"  # flags may contain shell metacharacters
```

## Network Fetch Hardening

All `curl` calls must include: `--proto '=https' --tlsv1.3 --max-time 30`
All `wget` calls must include: `--https-only --max-redirect=3`
Never fetch and pipe directly to `bash` without verifying a checksum first.

## sudo Usage

- Never use `sudo sh -c "..."` with interpolated variables
- Prefer `printf '...\n' | sudo tee /path` for writing privileged files
- Document every `sudo` call with an inline comment explaining why root is needed
