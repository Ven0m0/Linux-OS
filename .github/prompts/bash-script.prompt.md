# Bash Agent Execution Prompt

## Context
Repository: Ven0m0/Template
Target: Bash scripts and shell content
Standards: `.github/instructions/bash.instructions.md`
Platforms: Arch/Wayland, Debian/Raspbian, Termux

## Task: ${TASK_NAME}

### Inputs
- Files: ${FILES_TO_PROCESS}
- Trigger: ${TRIGGER_TYPE}
- Scope: ${SCOPE_PATTERN}

### Execution Steps

1. **Discover**
   ```bash
   fd -e sh -e bash -t f -H -E . git
   ```
2. **Lint**
   ```bash
   shellcheck --severity=style --format=gcc ${files}
   ```
3. **Format**
   ```bash
   shfmt -i 2 -ci -sr -l -w ${files}
   ```
4. **Validate**
   - Shebang: `#!/usr/bin/env bash`
   - Strict mode: `set -Eeuo pipefail`
   - Shell options present
   - Cleanup traps defined
5. **Test**
   - Run bats-core if tests exist
   - Verify on Arch (if available)
   - Verify on Debian (if available)
6. **Report**
   - Files modified: ${count}
   - Warnings fixed: ${count}
   - Remaining issues: ${count}
   - Risk level: ${LOW|MEDIUM|HIGH}
### Success Criteria
- ✅ Zero shellcheck warnings (severity=style)
- ✅ All files formatted consistently
- ✅ No breaking changes introduced
- ✅ Tests pass (if present)
- ✅ PR created with full changelog
### Output Format
```markdown
## Summary
- **Task**: ${TASK_NAME}
- **Files**: ${count} modified
- **Warnings**: ${count} fixed
- **Risk**: ${level}
## Changes
${detailed_changelog}
## Test Results
${test_output}
## Commands Run
```bash
${commands_executed}
```
## Next Steps
${manual_review_items}
```
### Failure Handling
- Log error details
- Create issue with reproduction steps
- Tag with `agent:failed` and `needs-human`
- Include exit code and stack trace
### Quality Gates
- All changes in atomic commits
- Format commits separate from logic commits
- Each commit message starts with `[agent] ${task}:`
- PR body includes platform test steps****
```
