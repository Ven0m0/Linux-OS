# Quick Start Guide

## Installation

```bash
# Copy to working directory
cp codesum.py /usr/local/bin/codesum.py
cp codesum /usr/local/bin/codesum
chmod +x /usr/local/bin/codesum*

# Or use locally
chmod +x codesum.py codesum
./codesum .
```

## Basic Usage

### 1. Simple Summary
```bash
# Current directory
./codesum

# Specific project
./codesum ~/projects/myapp

# With compression (requires API key)
export OPENAI_API_KEY="sk-..."
./codesum . -c
```

### 2. Traceback Analysis
```bash
# Interactive (paste traceback)
./codesum trace ~/projects/myapp

# From error output
python app.py 2>&1 | ./codesum trace .

# Direct string
./codesum . -t "Traceback (most recent call last):
  File \"app.py\", line 42, in func
    result = 1/0
ZeroDivisionError: division by zero"
```

### 3. Multi-LLM Providers
```bash
# OpenAI (default)
export OPENAI_API_KEY="sk-..."
./codesum openai .

# Gemini (free tier: 60 req/min)
export GEMINI_API_KEY="..."
./codesum gemini .

# Claude (Anthropic)
export ANTHROPIC_API_KEY="sk-ant-..."
./codesum claude .
```

### 4. Remote Repositories
```bash
# Clone and summarize
./codesum repo https://github.com/user/project

# With filters
./codesum repo https://github.com/user/project -i "test/*" "*.md"

# Full code for specific files
./codesum repo https://github.com/user/project --print-full "main.py"
```

### 5. Pattern Matching
```bash
# Full content for main files
./codesum . --print-full "main.py" "app.py" "__init__.py"

# Full content for tests, ignore build
./codesum . --print-full "*test*.py" -i "build/*" "dist/*"

# Specific file types
./codesum . --print-full "*.config.py" "settings.py"
```

## Common Workflows

### Debug Flow
```bash
# Run failing code
python myapp.py 2>error.log

# Generate context
./codesum . -t "$(cat error.log)"

# Result in .summary_files/code_summary.md
```

### Pre-Commit Hook
```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash
codesum . --hook -c --llm gemini &>/dev/null &
```

### Claude Code Integration
```bash
# Generate context
./codesum . -c --llm claude

# Copy to clipboard (Wayland)
./codesum . | wl-copy

# Or use in session
claude-code . --context .summary_files/code_summary.md
```

### CI/CD Pipeline
```bash
# GitHub Actions
- name: Generate codebase summary
  run: |
    python3 codesum.py . -c --llm gemini > summary.md
    
- name: Upload artifact
  uses: actions/upload-artifact@v3
  with:
    name: code-summary
    path: summary.md
```

## API Keys

### OpenAI
1. Get key: https://platform.openai.com/api-keys
2. Set: `export OPENAI_API_KEY="sk-..."`
3. Models: `gpt-4o-mini` (default), `gpt-4o`, `gpt-4-turbo`

### Gemini (Free Tier)
1. Get key: https://aistudio.google.com/app/apikey
2. Set: `export GEMINI_API_KEY="..."`
3. Models: `gemini-1.5-flash` (default), `gemini-1.5-pro`
4. Limits: 60 requests/minute (free)

### Claude
1. Get key: https://console.anthropic.com/settings/keys
2. Set: `export ANTHROPIC_API_KEY="sk-ant-..."`
3. Models: `claude-3-5-haiku-20241022` (default), `claude-3-5-sonnet-20241022`

## Advanced Options

```bash
# All flags
codesum.py [PROJECT] [OPTIONS]

OPTIONS:
  --mcp              MCP tool mode (JSON output)
  --hook             Silent hook mode (path to stdout)
  -c, --compress     Enable AI compression
  --llm PROVIDER     Choose: openai, gemini, claude
  --api-key KEY      Override env API key
  --model NAME       Specific model name
  --print-full PATTERNS  Full content for matching files
  -i, --ignore PATTERNS  Ignore file patterns
  -t, --traceback TEXT   Traceback string for analysis
```

## Output Format

### Standard Output
```markdown
# Project Summary: myapp
Files: 42 | Mode: Raw | LLM: openai

## Structure
myapp/
  ├── main.py
  ├── utils.py
  └── config.py

---

## File: main.py
Tokens: 234 | Size: 1024b
```python
def main() -> None:
  ...
```

### With Traceback
```markdown
---
## Traceback Analysis
File: app.py, Line: 42, Function: process_data

Function Context:
```python
def process_data(a, b):
  result = divide(a, b)
  return result * 2
```

Line Context:
    40: def process_data(a, b):
>>> 42:   result = divide(a, b)
    44:   return result * 2

Resolve this error.
```

## Performance Tips

1. **Use Gemini for free/fast compression** (60 req/min)
2. **Cache is automatic** (MD5-keyed, reuses compressed results)
3. **Ignore test files** to reduce token count: `-i "*test*"`
4. **Use --print-full sparingly** (full content increases tokens)
5. **Remote repos auto-cleanup** (temp dirs deleted after use)

## Troubleshooting

**"No text files found"**
- Check ignore patterns: `codesum . --ignore ""` (disable all)
- Verify directory: `ls -la`

**"API key not found"**
- Set environment: `export OPENAI_API_KEY="..."`
- Or pass directly: `--api-key "..."`

**"Traceback not parsed"**
- Ensure Python format: `File "...", line N`
- Use raw string: `-t '...'` not `-t "..."`

**"Import errors"**
- Check Python version: `python3 --version` (3.8+ required)
- Optional packages: `pip install tiktoken openai anthropic google-generativeai`
- Or use HTTP mode (no imports needed)

## Examples Gallery

### 1. Analyze Failing Test
```bash
pytest tests/ -v 2>fail.log
./codesum . -t "$(cat fail.log)" --print-full "*test*.py"
```

### 2. Compare Implementations
```bash
# Summarize competitor repo
./codesum repo https://github.com/competitor/tool -c --llm gemini

# Compare with yours
./codesum . -c --llm gemini

# Diff outputs
diff <(./codesum repo ...) <(./codesum .)
```

### 3. Code Review Prep
```bash
# Generate summary of feature branch
git checkout feature/new-api
./codesum . -c --llm claude --print-full "api/*"

# Include in PR description
gh pr create --body "$(cat .summary_files/code_summary.md)"
```

### 4. Documentation Context
```bash
# Full docs, summarized code
./codesum . --print-full "*.md" "README*" -i "*test*"

# Feed to Claude for doc generation
claude-code . --context .summary_files/code_summary.md \
  --prompt "Generate comprehensive API documentation"
```

## Integration with Tools

### Claude Code
```bash
# Auto-context on session start
# ~/.config/claude-code/hooks/pre-session.sh
codesum . --hook -c --llm claude &
```

### VSCode Task
```json
{
  "label": "Generate Code Summary",
  "type": "shell",
  "command": "codesum . -c --llm gemini",
  "problemMatcher": []
}
```

### Make Target
```makefile
.PHONY: summary
summary:
	@codesum . -c --llm gemini
	@echo "Summary: .summary_files/code_summary.md"
```

### Taskfile
```yaml
version: '3'
tasks:
  summary:
    desc: Generate code summary
    cmds:
      - codesum . -c --llm gemini
```
