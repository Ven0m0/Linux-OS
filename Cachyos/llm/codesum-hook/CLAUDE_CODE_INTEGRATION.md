# Claude Code Hook Installation

## Quick Setup

1. **Copy files to hook directory:**
```bash
# Create hooks directory
mkdir -p ~/.config/claude-code/hooks

# Copy codesum files
cp codesum.py ~/.config/claude-code/hooks/
cp codesum-mcp.py ~/.config/claude-code/hooks/
cp codesum-hook.sh ~/.config/claude-code/hooks/

# Make executable
chmod +x ~/.config/claude-code/hooks/*.{py,sh}
```

2. **Create tool configuration:**
```bash
cat > ~/.config/claude-code/tools/codesum.json <<'EOF'
{
  "name": "codesum",
  "description": "Generate optimized code summary with 10-20x token reduction",
  "command": ["python3", "$HOOKS_DIR/codesum-mcp.py", "$PROJECT_DIR"],
  "type": "context",
  "trigger": "manual"
}
EOF
```

## Usage Patterns

### 1. Manual Invocation
```bash
# In any project directory
~/.config/claude-code/hooks/codesum-mcp.py .
```

### 2. As Pre-Session Context
Create `~/.config/claude-code/hooks/pre-session.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Auto-generate context for every new session
python3 ~/.config/claude-code/hooks/codesum-mcp.py "$PROJECT_DIR"
```

### 3. Git Hook Integration
Create `.git/hooks/pre-commit`:
```bash
#!/usr/bin/env bash
# Update context on every commit
python3 ~/.config/claude-code/hooks/codesum-mcp.py . >/dev/null 2>&1 &
exit 0
```

## Advanced: AI Compression Mode

For large projects, enable compression:
```bash
# Set API key
export OPENAI_API_KEY="sk-..."

# Run with compression
python3 codesum.py --compress --all
```

## Integration with MCP Servers

If using basic-memory MCP:
```bash
# Store summary as memory artifact
python3 codesum-mcp.py . | \
  basic-memory write_note \
    --folder "context" \
    --title "codebase-$(date +%Y%m%d)" \
    --content -
```

## Workflow Examples

### Example 1: Quick Project Overview
```bash
# Generate summary, pipe to Claude
codesum-mcp.py ~/projects/myapp | claude-code --context -
```

### Example 2: Incremental Updates
```bash
# Only regenerate if files changed
find . -type f -newer .summary_files/code_summary.md -print -quit | \
  grep -q . && codesum-mcp.py .
```

### Example 3: Filtered Context
```bash
# Only summarize changed files in last commit
git diff-tree --no-commit-id --name-only -r HEAD | \
  xargs -I {} sh -c 'test -f {} && echo {}' | \
  while read f; do
    echo "## $f"
    cat "$f"
  done
```

## Performance Tuning

### Ignore Patterns
Add to `.summary_files/ignore_patterns.txt`:
```
# Project-specific ignores
*.generated.py
*_pb2.py
migrations/
fixtures/
```

### Token Budget
Limit summary size:
```python
# In codesum.py, modify create_summary():
MAX_TOKENS = 50000  # ~200KB context
if total_tokens > MAX_TOKENS:
    # Prioritize by file importance
    files.sort(key=lambda e: e.size)
    files = files[:100]  # Top 100 files
```

## Troubleshooting

**No wl-copy found:**
```bash
# Install wl-clipboard (Wayland)
sudo pacman -S wl-clipboard  # Arch
sudo apt install wl-clipboard  # Debian/Ubuntu
```

**Permission denied:**
```bash
chmod +x ~/.config/claude-code/hooks/*.py
```

**Import errors:**
```bash
# Verify Python path
export PYTHONPATH="$HOME/.config/claude-code/hooks:$PYTHONPATH"
```

## File Structure
```
~/.config/claude-code/
├── hooks/
│   ├── codesum.py           # Core summarizer
│   ├── codesum-mcp.py       # MCP tool wrapper
│   ├── codesum-hook.sh      # Bash hook
│   └── pre-session.sh       # Auto-trigger
└── tools/
    └── codesum.json         # Tool descriptor
```

## Verification

Test the hook:
```bash
cd ~/projects/test-project
python3 ~/.config/claude-code/hooks/codesum-mcp.py . | head -20
```

Expected output:
```
# Code Summary
**Project:** /home/user/projects/test-project
**Files:** 42

## Structure
...
```
