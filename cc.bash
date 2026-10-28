# cc — Claude Code wrapper, bash entry point. The logic lives in bin/claude-cc.
# Source this file from ~/.bashrc.

__cc_bin="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/bin"
case ":$PATH:" in
    *":$__cc_bin:"*) ;;
    *) PATH="$__cc_bin:$PATH" ;;
esac
unset __cc_bin

function cc  { CC_PROJECT_BASE="${CC_PROJECT_BASE:-}" CC_WT_BASE="${CC_WT_BASE:-}" claude-cc "$@"; }
function cct { cc --teams "$@"; }
