#!/usr/bin/env bash
# cc — Claude Code wrapper installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash

set -euo pipefail

INSTALL_DIR="${CC_INSTALL_DIR:-$HOME/.config/zsh/claude-cc}"
REPO_URL="https://github.com/Ahngbeom/claude-cc.git"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
SOURCE_LINE="source \"$INSTALL_DIR/cc.zsh\""

echo "cc installer"
echo "============"
echo ""

# ── Download ────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "→ Updating existing installation at $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "→ Installing to $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

# ── .zshrc update ───────────────────────────────────
if grep -qF "$SOURCE_LINE" "$ZSHRC" 2>/dev/null; then
    echo "→ .zshrc already sources cc.zsh — skipping."
else
    echo "" >> "$ZSHRC"
    echo "# cc — Claude Code wrapper (https://github.com/Ahngbeom/claude-cc)" >> "$ZSHRC"
    echo "$SOURCE_LINE" >> "$ZSHRC"
    echo "→ Added source line to $ZSHRC"
fi

# ── Oh My Zsh hint ──────────────────────────────────
if [[ -n "${ZSH_CUSTOM:-}" ]]; then
    echo ""
    echo "Oh My Zsh detected. Alternatively, symlink for plugin-style loading:"
    echo "  ln -sf \"$INSTALL_DIR\" \"\${ZSH_CUSTOM}/plugins/cc\""
    echo "  # Then add 'cc' to plugins=(...) in your .zshrc"
fi

echo ""
echo "Done! Restart your shell or run:"
echo "  source $INSTALL_DIR/cc.zsh"
echo ""
echo "Optional: set these in .zshrc before the source line to customize paths:"
echo "  export CC_PROJECT_BASE=\"\$HOME/my-projects\""
echo "  export CC_WT_BASE=\"\$HOME/my-worktrees\""
