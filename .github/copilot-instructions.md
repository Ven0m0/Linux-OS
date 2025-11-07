# Copilot Master Instructions

## 1. Core Principles

- **Autonomous Execution**: Execute tasks immediately. Edit existing code and configurations without hesitation. Confirm only for large-scale or potentially destructive changes.
- **Quality & Verification**: Automatically run formatters, linters, and other checks. Verify facts and avoid speculation.
- **Efficiency**: Prioritize token efficiency and concise communication.
- **Rethink Before Acting**: If there are multiple viable approaches, list pros and cons before proceeding. Prefer editing existing files over creating new ones.
- **Debt Elimination**: Aggressively remove unused code, dependencies, and complexity. Less code is less debt.

## 2. Communication Style

- **Language**: English (Technical)
- **Style**: Professional, concise, advanced, and blunt.
- **Token Efficiency**: Use the symbol and abbreviation system defined in `prompts/token-efficiency.prompt.md`.

## 3. Development Practices

### Change & Commit Hygiene
- **TDD Workflow**: Follow a Red → Green → Refactor cycle.
- **Separate Concerns**: Strictly separate structural changes (formatting) from behavioral changes (logic). Never mix them in the same commit.
- **Atomic Commits**: Commits must be small, frequent, and independent. A commit is ready only when:
    1. All tests pass.
    2. Linters produce zero warnings.
    3. It represents a single, logical unit of work.
    4. The commit message is clear and concise.

### Code Quality
- **Single Responsibility**: Functions and modules should do one thing well.
- **Loose Coupling**: Use interfaces and abstractions to reduce dependencies.
- **Fail Fast**: Use early returns and guard clauses.
- **DRY**: Eliminate duplicate logic and code immediately.

## 4. Language-Specific Guidelines

### **Bash**
- **Strict Mode**: `set -Eeuo pipefail`, `shopt -s nullglob globstar`, `IFS=$'\n\t'`, `export LC_ALL=C LANG=C`.
- **Idioms**: Prefer native bashisms: arrays, `mapfile -t`, `[[...]]`, parameter expansion. Avoid parsing `ls`, `eval`, and backticks.
- **Tooling**: Prefer modern Rust-based tools (`fd`, `rg`, `bat`, `sd`, `zoxide`) with fallbacks to traditional counterparts (`find`, `grep`, `cat`, `sed`, `cd`).
- **Structure**: Use the canonical template in `prompts/bash-script.prompt.md`.
- **Linting**: `shfmt -i 2 -ci -sr`, `shellcheck` (zero warnings), `shellharden`.

### **Rust**
- **Error Handling**: Use `Result<T, E>` and the `?` operator. Use `thiserror` or `anyhow` for rich errors. Avoid `unwrap()`/`expect()` in library code.
- **Style**: Format with `rustfmt`. Lint with `cargo clippy -- -D warnings`.
- **Patterns**: Use the builder pattern for complex objects, `serde` for serialization, `rayon` for parallelism. Prefer iterators and borrowing over indexing and `clone()`.
- **API Design**: Implement common traits (`Debug`, `Clone`, `Default`, etc.). Use newtypes for type safety. Public APIs must be documented.

### **Python**
- **Style**: Follow PEP 8. Format with `black` or `ruff format`. Lint with `ruff` or `flake8`.
- **Typing**: Use type hints (`typing` module) for all functions and variables.
- **Docstrings**: Follow PEP 257.
- **Structure**: Break complex functions into smaller, single-purpose units.

### **Markdown**
- **Structure**: Use `##` for H2 and `###` for H3. Limit nesting.
- **Code Blocks**: Use fenced code blocks with language identifiers.
- **Line Length**: Soft wrap at 80-100 characters for readability.

## 5. Performance Optimization
- **Measure First**: Profile and benchmark before optimizing.
- **Focus on Hot Paths**: Optimize the most frequently executed code.
- **Caching**: Use in-memory (Redis), DB, and frontend caching where appropriate. Invalidate correctly.
- **Concurrency**: Use async I/O, thread/worker pools, and batch processing.
- **Database**: Use indexes, analyze query plans (`EXPLAIN`), and avoid N+1 queries.

## 6. GitHub Actions
- **Security**: Use OIDC for cloud auth, set least-privilege `permissions` for `GITHUB_TOKEN`, and scan for secrets.
- **Performance**: Use caching for dependencies and build outputs. Use matrix strategies for parallel jobs.
- **Structure**: Maintain clean, modular workflows. Use composite actions or reusable workflows to reduce duplication.
- **Testing**: Integrate unit, integration, and E2E tests. Report results clearly.

---
