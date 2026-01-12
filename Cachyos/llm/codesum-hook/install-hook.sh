#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
IFS=$'\n\t'

# Claude Code hook installer
HOOKS_DIR="${HOME}/.config/claude-code/hooks"
TOOLS_DIR="${HOME}/.config/claude-code/tools"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

msg(){ printf '%s\n' "$@"; }
die(){ printf '%s\n' "$1" >&2; exit "${2:-1}"; }

# Create directories
msg "📁 Creating directories..."
mkdir -p "$HOOKS_DIR" "$TOOLS_DIR"

# Copy files
msg "📋 Copying codesum files..."
cp -v "$SCRIPT_DIR/codesum.py" "$HOOKS_DIR/"
cp -v "$SCRIPT_DIR/codesum-mcp.py" "$HOOKS_DIR/"
cp -v "$SCRIPT_DIR/codesum-hook.sh" "$HOOKS_DIR/"

# Make executable
msg "🔧 Setting permissions..."
chmod +x "$HOOKS_DIR"/*.{py,sh}

# Create tool descriptor
msg "📝 Creating tool configuration..."
cat > "$TOOLS_DIR/codesum.json" <<'EOF'
{
  "name": "codesum",
  "description": "Generate optimized code summary (10-20x token reduction)",
  "command": ["python3", "$HOOKS_DIR/codesum-mcp.py", "$PROJECT_DIR"],
  "type": "context",
  "trigger": "manual",
  "output": "markdown"
}
EOF

# Create pre-session hook (optional)
if [[ ! -f "$HOOKS_DIR/pre-session.sh" ]]; then
  msg "🪝 Creating pre-session hook..."
  cat > "$HOOKS_DIR/pre-session.sh" <<'EOF'
#!/usr/bin/env bash
# Auto-generate context for new sessions
set -euo pipefail
python3 "$HOOKS_DIR/codesum-mcp.py" "${PROJECT_DIR:-.}" 2>/dev/null || true
EOF
  chmod +x "$HOOKS_DIR/pre-session.sh"
fi

# Test installation
msg "✅ Testing installation..."
if python3 "$HOOKS_DIR/codesum-mcp.py" "$SCRIPT_DIR" >/dev/null 2>&1; then
  msg "✓ Installation successful!"
else
  die "✗ Test failed - check Python dependencies" 1
fi

# Print usage
msg ""
msg "🚀 Installation complete!"
msg ""
msg "Usage:"
msg "  # Manual invocation"
msg "  cd ~/projects/myapp"
msg "  python3 $HOOKS_DIR/codesum-mcp.py ."
msg ""
msg "  # With AI compression (requires OPENAI_API_KEY)"
msg "  export OPENAI_API_KEY='sk-...'"
msg "  python3 $HOOKS_DIR/codesum.py --compress --all"
msg ""
msg "  # Auto-trigger on session start"
msg "  # Edit: $HOOKS_DIR/pre-session.sh"
msg ""
msg "Files installed:"
msg "  $HOOKS_DIR/codesum.py"
msg "  $HOOKS_DIR/codesum-mcp.py"
msg "  $HOOKS_DIR/codesum-hook.sh"
msg "  $TOOLS_DIR/codesum.json"
