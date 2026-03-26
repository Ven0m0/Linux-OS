---
description: Generate a conventional commit message from staged diff
agent: code
---

Staged changes:
!`git diff --staged`

Generate a conventional commit message for these changes.

Rules:
- Type: `fix` (bug), `feat` (new behaviour), `chore` (tooling/CI/docs), `refactor` (structural, no behaviour delta), `perf` (performance)
- Scope: script basename without `.sh` (e.g. `up`, `clean`, `raspi-f2fs`)
- Subject: imperative mood, ≤72 chars, lowercase, no trailing period
- NEVER mix structural and behavioral changes in one commit message — flag if the diff contains both
- Body: only if the "why" is non-obvious

Format:
```
<type>(<scope>): <subject>

[optional body]
```

Output only the commit message text, no markdown fences.
