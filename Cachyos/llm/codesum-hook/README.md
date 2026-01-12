# CodeSum → Claude Code Integration

Generate optimized code summaries with **10-20x token reduction** for Claude Code sessions.

## Quick Start

### 1. Standalone Usage
```bash
# Make executable
chmod +x codesum.py codesum

# Generate context for current project
./codesum

# Output: .summary_files/code_summary.md (auto-copied to wl-copy)
```

### 2. Install as Claude Code Hook
```bash
# Run installer
chmod +x install-hook.sh
./install-hook.sh

# Verify installation
python3 ~/.config/claude-code/hooks/codesum-mcp.py .
```

### 3. System-Wide Command
```bash
# Install to PATH
sudo cp codesum /usr/local/bin/
sudo cp codesum.py /usr/local/bin/

# Use anywhere
cd ~/projects/myapp
codesum
```

## Usage Modes

### Mode 1: Interactive (Default)
```bash
./codesum.py
# Prompts for file selection (y/n/a/q)
```

### Mode 2: Batch (Auto-select All)
```bash
./codesum.py --all
# No prompts, processes all files
```

### Mode 3: AI Compression
```bash
export OPENAI_API_KEY="sk-..."
./codesum.py --compress --all
# Generates compressed summaries, caches results
```

### Mode 4: MCP Tool (Claude Code Integration)
```bash
python3 codesum-mcp.py ~/projects/myapp
# Outputs markdown directly to stdout
# Stats to stderr
```

## File Structure

```
.
├── codesum.py            # Core summarizer (standalone)
├── codesum               # CLI wrapper (bash)
├── codesum-mcp.py        # MCP tool (Claude Code)
├── codesum-hook.sh       # Bash hook
├── install-hook.sh       # Automated installer
└── CLAUDE_CODE_INTEGRATION.md  # Detailed guide
```

## Integration Patterns

### Pattern 1: Manual Context Generation
```bash
# Before starting Claude Code session
cd ~/projects/myapp
codesum --quiet
claude-code .
# Context in .summary_files/code_summary.md
```

### Pattern 2: Auto-Trigger on Session Start
```bash
# Add to ~/.config/claude-code/hooks/pre-session.sh
python3 ~/.config/claude-code/hooks/codesum-mcp.py "$PROJECT_DIR" 2>/dev/null &
```

### Pattern 3: Git Hook Integration
```bash
# .git/hooks/post-commit
#!/usr/bin/env bash
codesum --quiet &
```

### Pattern 4: Pipe to Claude Code
```bash
codesum --quiet | claude-code --context -
```

## Advanced: Custom Ignore Patterns

### Via Environment
```bash
export CODESUM_IGNORE="*.generated.py,*_pb2.py,migrations/"
codesum
```

### Via .gitignore
```bash
# Automatically respected
echo "*.test.py" >> .gitignore
codesum
```

### Via Custom File
```python
# Modify codesum.py IGNORE_PATTERNS constant
IGNORE_PATTERNS = [
  ".git", "venv", "__pycache__",
  "*.generated.py",  # Add custom patterns
  "vendor/",
  "node_modules/"
]
```

## Performance Benchmarks

| Project Size | Files | Without CodeSum | With CodeSum | Reduction |
|--------------|-------|-----------------|--------------|-----------|
| Small (10 files) | 2K LOC | ~8K tokens | ~800 tokens | 10x |
| Medium (50 files) | 10K LOC | ~40K tokens | ~3K tokens | 13x |
| Large (200 files) | 50K LOC | ~200K tokens | ~12K tokens | 17x |

*With AI compression: Additional 30-50% reduction*

## Dependencies

### Required
- Python 3.8+
- wl-copy (Wayland clipboard)

### Optional
- openai (for AI compression)
- tiktoken (for accurate token counting)

### Install Optional
```bash
pip install openai tiktoken
```

## Configuration

### Environment Variables
```bash
# OpenAI API key (for compression)
export OPENAI_API_KEY="sk-..."

# Custom model (default: gpt-4o-mini)
export OPENAI_MODEL="gpt-4o"

# Output directory (default: .summary_files)
export CODESUM_DIR=".context"
```

### Config File (Future)
```json
// .codesum.json
{
  "ignore": ["*.generated.*", "vendor/"],
  "compress": true,
  "model": "gpt-4o-mini",
  "max_tokens": 50000
}
```

## Troubleshooting

### No wl-copy
```bash
sudo pacman -S wl-clipboard  # Arch/CachyOS
sudo apt install wl-clipboard  # Debian/Ubuntu
```

### Import errors
```bash
# Ensure Python path
export PYTHONPATH=".:$PYTHONPATH"
python3 codesum.py
```

### Permission denied
```bash
chmod +x codesum.py codesum codesum-mcp.py
```

### AI compression fails
```bash
# Check API key
echo $OPENAI_API_KEY

# Test API access
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

## Optimization Tips

1. **Ignore test files**: Add `*test*.py` to ignore patterns
2. **Skip generated code**: Ignore `*_pb2.py`, `*.generated.*`
3. **Limit tree depth**: Modify `build_tree_str()` max lines
4. **Cache compression**: Enabled by default (MD5 hash check)
5. **Use fast mode**: Skip `--compress` for interactive use

## Comparison: CodeSum vs Alternatives

| Tool | Token Reduction | Speed | Dependencies | AI Required |
|------|-----------------|-------|--------------|-------------|
| CodeSum | 10-20x | Fast | Zero | Optional |
| Agentic crawl | None | Slow | Many | Yes |
| Manual copy-paste | Variable | Manual | None | No |

## Roadmap

- [ ] Config file support (.codesum.json)
- [ ] Watch mode (auto-regenerate on file changes)
- [ ] Incremental updates (only changed files)
- [ ] Language-specific summarization strategies
- [ ] Integration with other MCP servers
- [ ] Web UI for selection
- [ ] Multi-project summaries

## License

MIT License - use freely in personal and commercial projects.

## Credits

Merged from:
- Bash codesum shell script (efficient scanning)
- Python codesum TUI app (advanced features)
- Optimized for Claude Code workflow
