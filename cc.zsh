# cc — Claude Code wrapper, zsh entry point. The logic lives in bin/claude-cc.
# Source this file from ~/.zshrc, or load it as the Oh My Zsh plugin "cc".

() {
    local bin="${1:A:h}/bin"
    [[ -x "$bin/claude-cc" ]] || bin="$HOME/.config/zsh/claude-cc/bin"
    (( ${path[(Ie)$bin]} )) || path=("$bin" $path)
} "$0"

function cc  { CC_PROJECT_BASE="${CC_PROJECT_BASE:-}" CC_WT_BASE="${CC_WT_BASE:-}" claude-cc "$@" }
function cct { cc --teams "$@" }
