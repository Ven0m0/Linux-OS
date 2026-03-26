# Testing Rules

## Static Analysis (mandatory before any commit)

```bash
# ShellCheck — zero warnings at style severity
shellcheck --severity=style <file.sh>

# shfmt — zero diff output means clean
shfmt -i 2 -ci -sr -d <file.sh>
```

Both must pass for every `.sh` file outside `Cachyos/Scripts/WIP/`.

## CI Gate

The `lint-format.yml` workflow runs `./lint-format.sh -c` on every push to `main/master/claude/**`.
A failing lint check blocks merge. Fix locally with `./lint-format.sh` (no `-c`).

## Unit Tests (bats-core)

- Framework: `bats-core` for function-level tests
- Test files: `*.bats` co-located with the script under test or in `tests/`
- Each public function with non-trivial logic should have a bats test
- Mock external commands with bats `stub` helpers; never require root for unit tests

## Integration Tests

- Test on both Arch and Debian (distro compat is a hard requirement)
- F2FS imaging scripts (`raspi-f2fs.sh`, `dietpi-chroot.sh`) require a loop device test environment
- Do not merge Pi imaging changes without a loop-device dry-run

## Performance Benchmarks

Use `hyperfine` for any script that runs on a hot path or is user-facing:
```bash
hyperfine --warmup 3 './script.sh --dry-run'
```

## Lint Exclusions

Scripts in `Cachyos/Scripts/WIP/` are explicitly excluded from all linting.
Do NOT add `# shellcheck disable` comments to pass CI — fix the issue or move to WIP.
Acceptable disable list (from `.shellcheckrc`): SC1079, SC1078, SC1073, SC1072, SC1083,
SC2086, SC1090, SC1091, SC2002, SC2016, SC2034, SC2154, SC2155, SC2236, SC2250, SC2312.

## Syntax Check Before Save

Run `bash -n <file.sh>` to catch syntax errors before running shellcheck.
