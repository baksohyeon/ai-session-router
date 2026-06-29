#!/usr/bin/env sh
# install.sh — idempotent bootstrap for the ai session router.
# Safe to re-run. Creates directories + config, symlinks ~/.local/bin/ai.
# Never overwrites existing config; never touches existing ~/.claude / ~/.codex.
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_DIR/bin/ai"
BIN_DST="$HOME/.local/bin/ai"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-session-router"
CFG="$CFG_DIR/router.env"

# Defaults (edit CFG afterwards, or pre-seed via env before running).
PERSONAL_WS="${AI_PERSONAL_WS:-$HOME/dev/personal}"
COMPANY_WS="${AI_COMPANY_WS:-$HOME/dev/work}"

echo "== ai session router install =="
echo "repo: $REPO_DIR"

# 1. directories ------------------------------------------------------------
mkdir -p \
  "$PERSONAL_WS/.ai-logs" \
  "$COMPANY_WS/.ai-logs" \
  "$HOME/.claude-personal" "$HOME/.claude-company" \
  "$HOME/.codex-personal" "$HOME/.codex-company" \
  "$HOME/.ai-shared/mcp" "$HOME/.ai-shared/router" \
  "$HOME/.local/bin" "$CFG_DIR"
echo "  directories ok"

# 2. config (never clobber) -------------------------------------------------
if [ -f "$CFG" ]; then
  echo "  config exists, leaving as-is: $CFG"
else
  cat > "$CFG" <<EOF
# ai session router config — edit freely
AI_PERSONAL_WS="$PERSONAL_WS"
AI_COMPANY_WS="$COMPANY_WS"
AI_CLAUDE_ROOT_PREFIX="\$HOME/.claude-"
AI_CODEX_ROOT_PREFIX="\$HOME/.codex-"
AI_CHROME_COMPANY_PROFILE="Work"
AI_COMPANY_CHATGPT_URL="https://chatgpt.com/"
AI_COMPANY_CLAUDE_URL="https://claude.ai/"
EOF
  echo "  wrote config: $CFG"
fi

# 3. shared docs (copy if missing) -----------------------------------------
[ -f "$HOME/.ai-shared/README.md" ] || cp "$REPO_DIR/share/README.md" "$HOME/.ai-shared/README.md" 2>/dev/null || true

# 4. symlink the binary -----------------------------------------------------
if [ -L "$BIN_DST" ] || [ ! -e "$BIN_DST" ]; then
  ln -sf "$BIN_SRC" "$BIN_DST"
  echo "  symlinked: $BIN_DST -> $BIN_SRC"
else
  echo "  WARNING: $BIN_DST exists and is not a symlink; not overwriting."
  echo "           back it up and re-run, or symlink manually."
fi
chmod +x "$BIN_SRC" 2>/dev/null || true

# 5. PATH hint --------------------------------------------------------------
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) echo "  NOTE: add ~/.local/bin to PATH, e.g.:"
     echo '        echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.zshrc' ;;
esac

echo "done. run: ai doctor"
