#!/usr/bin/env bash
# cc — Claude Code wrapper installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash

set -euo pipefail

INSTALL_DIR="${CC_INSTALL_DIR:-$HOME/.config/zsh/claude-cc}"
REPO_URL="https://github.com/Ahngbeom/claude-cc.git"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
BASHRC="$HOME/.bashrc"
LOGIN_SHELL="$(basename "${SHELL:-}")"

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

# ── rc file update ──────────────────────────────────
add_source_line() {
    local rc="$1" line="source \"$INSTALL_DIR/$2\""
    if grep -qF "$line" "$rc" 2>/dev/null; then
        echo "→ $rc already sources $2 — skipping."
    else
        {
            echo ""
            echo "# cc — Claude Code wrapper (https://github.com/Ahngbeom/claude-cc)"
            echo "$line"
        } >> "$rc"
        echo "→ Added source line to $rc"
    fi
}

configured=0
if [[ "$LOGIN_SHELL" == zsh || -f "$ZSHRC" ]]; then
    add_source_line "$ZSHRC" cc.zsh
    configured=1
fi
if [[ "$LOGIN_SHELL" == bash || -f "$BASHRC" ]]; then
    add_source_line "$BASHRC" cc.bash
    configured=1
    if [[ "$LOGIN_SHELL" == bash && "$(uname -s)" == Darwin ]]; then
        echo "  macOS bash login shells read ~/.bash_profile — make sure it sources ~/.bashrc."
    fi
fi
if (( ! configured )); then
    echo "→ No zsh or bash rc file found. Add one of these to your shell's rc file:"
    echo "    source \"$INSTALL_DIR/cc.zsh\"    # zsh"
    echo "    source \"$INSTALL_DIR/cc.bash\"   # bash"
    echo "  Other shells can run $INSTALL_DIR/bin/claude-cc directly."
fi

# ── Oh My Zsh hint ──────────────────────────────────
if [[ -n "${ZSH_CUSTOM:-}" ]]; then
    echo ""
    echo "Oh My Zsh detected. Alternatively, symlink for plugin-style loading:"
    echo "  ln -sf \"$INSTALL_DIR\" \"\${ZSH_CUSTOM}/plugins/cc\""
    echo "  # Then add 'cc' to plugins=(...) in your .zshrc"
fi

echo ""
echo "Done! Open a new shell to start using cc."
echo ""
echo "Optional: set these in your rc file to customize paths:"
echo "  export CC_PROJECT_BASE=\"\$HOME/my-projects\""
echo "  export CC_WT_BASE=\"\$HOME/my-worktrees\""
