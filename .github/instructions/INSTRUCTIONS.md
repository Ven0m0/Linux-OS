# LLM Instructions Index

**Purpose**: Centralized reference for all coding standards, patterns, and automation rules.

## Quick Reference

| File | Scope | Priority | Token Est |
|:-----|:------|:---------|:----------|
| `copilot-instructions.md` | All files | **Critical** | ~1.2k |
| `bash.instructions.md` | `**/*.sh` | High | ~3k |
| `token-efficient.md` | All LLM interactions | High | ~1k |
| `performance.instructions.md` | All code | Medium | ~5k |
| `actions.instructions.md` | `.github/workflows/*.yml` | Medium | ~12k |
| `rust.instructions.md` | `**/*.rs` | As-needed | ~2k |
| `python.instructions.md` | `**/*.py` | As-needed | ~0.5k |
| `markdown.instructions.md` | `**/*.md` | Low | ~0.8k |

## Priority Loading

### Always Load (< 5k tokens)

1. `copilot-instructions.md` - Core repo standards
2. `token-efficient.md` - Communication protocol
3. `bash.instructions.md` - Primary language (74.5%)

### Load by File Type

- **Shell scripts**: `bash.instructions.md` + `performance.instructions.md`
- **Workflows**: `actions.instructions.md`
- **Rust/Python**: Respective language files
- **Documentation**: `markdown.instructions.md`

### Load by Task

- **Performance work**: `performance.instructions.md`
- **Security audit**: Relevant sections from language files
- **Code review**: `token-efficient.md` + language file
- **Refactoring**: Language file + `performance.instructions.md`

## File Summaries

### copilot-instructions.md

**Essential repo patterns**:

- Repository structure (Home/, etc/, usr/)
- Bash standards (strict mode, idioms, tools)
- Tool preferences (fd→find, rg→grep, etc.)
- ast-grep integration
- Privilege/package management

**When**: Always load for any task

### bash.instructions.md

**Comprehensive Bash guide**:

- Canonical template with all helpers
- Security patterns (privilege, locking, cleanup)
- Performance optimizations
- Modern tool usage
- Platform compatibility (Arch/Debian/Termux)

**When**: Any shell script work

### token-efficient.md

**LLM communication protocol**:

- Symbols: →⇒∴∵✅❌⚠️⚡🔍🛡️
- Abbreviations: cfg, impl, perf, deps, val
- Output patterns: result-first, compressed
- Use cases: debugging, reviews, CI/CD

**When**: All LLM interactions

### performance.instructions.md

**Full-stack optimization**:

- Frontend: rendering, assets, network
- Backend: algorithms, concurrency, caching
- Database: queries, schema, transactions
- Profiling and benchmarking strategies

**When**: Performance-focused work

### actions.instructions.md

**GitHub Actions best practices**:

- Workflow structure and triggers
- Security (OIDC, secrets, permissions)
- Optimization (caching, matrix, artifacts)
- Testing and deployment strategies

**When**: CI/CD workflow changes

### Language-Specific

**rust.instructions.md**: Ownership, error handling, traits, API design
**python.instructions.md**: PEP 8, type hints, docstrings
**markdown.instructions.md**: Structure, formatting, front matter

**When**: Working with respective languages

## Agent Integration

### Bash Agent

- **Files**: `.github/agents/bash.{agent,instructions,prompt}.md`
- **Loads**: `copilot-instructions.md` + `bash.instructions.md`
- **Tasks**: Lint, format, optimize shell scripts

### Future Agents

- Performance optimizer: Loads `performance.instructions.md`
- Code janitor: Loads all for cleanup context
- Security auditor: Loads security sections

## Token Budget Strategy

### Minimal Context (~5k tokens)

```
copilot-instructions.md (1.2k)
+ token-efficient.md (1k)
+ bash.instructions.md (3k)
= ~5.2k tokens
```

### Standard Context (~10k tokens)

```
Minimal context (5.2k)
+ performance.instructions.md (5k)
= ~10.2k tokens
```

### Full Context (~25k tokens)

```
All instructions
+ Relevant agent files
+ Task-specific context
```

## Usage Patterns

### Code Review

1. Load `token-efficient.md` for output format
2. Load language-specific instructions
3. Load `performance.instructions.md` if relevant
4. Use compressed response format

### Refactoring

1. Load `copilot-instructions.md` for repo patterns
2. Load language instructions
3. Load `performance.instructions.md`
4. Follow "Edit > Create" principle

### New Feature

1. Load `copilot-instructions.md` for structure
2. Load language instructions
3. Check `actions.instructions.md` if CI/CD needed
4. Follow existing patterns

### Bug Fix

1. Load `token-efficient.md` for debugging format
2. Load minimal context
3. Apply "Subtraction > Addition"
4. Add regression test

## Maintenance

### When to Update

- New patterns emerge from repeated work
- Performance lessons learned
- Security vulnerabilities discovered
- Tool updates (new versions, deprecations)

### How to Update

1. Edit specific instruction file
2. Update this index if scope changes
3. Update token estimates
4. Notify in commit message

### Deprecation

- Mark sections as deprecated before removal
- Archive historical patterns if valuable
- Update agent configurations
