# cc — Claude Code wrapper function
# Subcommands: go, wt, clean, install, help
# All other arguments are passed directly to claude (preserves original alias behavior)
#
# Configuration (set in your .zshrc before sourcing this file):
#   export CC_PROJECT_BASE="$HOME/projects"   # default: ~/projects
#   export CC_WT_BASE="$HOME/worktrees"       # default: ~/worktrees

_CC_WT_BASE="${CC_WT_BASE:-$HOME/worktrees}"
_CC_PROJECT_BASE="${CC_PROJECT_BASE:-$HOME/projects}"

# ──────────────────────────────────────────────────
# cc go <path> [claude-opts...]
# ──────────────────────────────────────────────────
_cc_go() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cc go <path> [claude-opts...]" >&2
        return 1
    fi

    local target="$1"
    shift

    if [[ ! -d "$target" ]]; then
        echo "cc: path not found: $target" >&2
        return 1
    fi

    cd "$target" && claude "$@"
}

# ──────────────────────────────────────────────────
# cc wt [<project>] <branch> [claude-opts...]
# ──────────────────────────────────────────────────
_cc_worktree() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cc wt <branch> [claude-opts...]" >&2
        echo "       cc wt <project> <branch> [claude-opts...]" >&2
        echo "  branch:  feature/my-feature, fix/issue-123, etc." >&2
        echo "  project: absolute path or name under \$CC_PROJECT_BASE (omit to use current dir)" >&2
        return 1
    fi

    local project branch source_repo
    if [[ $# -eq 1 ]] || [[ "$2" == -* ]]; then
        # Single arg or second arg is a flag: cc wt <branch> [opts...]
        branch="$1"
        shift
        source_repo="$PWD"
        if ! git -C "$source_repo" rev-parse --git-dir &>/dev/null; then
            echo "cc: current directory is not a git repository: $source_repo" >&2
            return 1
        fi
    else
        # Two or more args: cc wt <project> <branch> [opts...]
        project="$1"
        branch="$2"
        shift 2

        # Resolve project path
        if [[ "$project" == /* || "$project" == ~* ]]; then
            source_repo="${~project}"  # tilde expansion
        else
            source_repo="$_CC_PROJECT_BASE/$project"
        fi
    fi

    if [[ ! -d "$source_repo" ]]; then
        echo "cc: project path not found: $source_repo" >&2
        return 1
    fi

    if ! git -C "$source_repo" rev-parse --git-dir &>/dev/null; then
        echo "cc: not a git repository: $source_repo" >&2
        return 1
    fi

    # Extract project name (last path component)
    local project_name="${source_repo:t}"

    # Worktree destination path (branch slashes map directly to subdirectories)
    local wt_dest="$_CC_WT_BASE/$project_name/$branch"

    # If worktree already exists, reuse it
    if [[ -d "$wt_dest" ]]; then
        echo "cc: reusing existing worktree: $wt_dest"
        cd "$wt_dest" && claude "$@"
        return $?
    fi

    # Create new worktree
    echo "cc: creating worktree..."
    echo "  source: $source_repo"
    echo "  path:   $wt_dest"
    echo "  branch: $branch"

    # Create parent directory
    mkdir -p "${wt_dest:h}"

    # Fetch then check branch existence
    echo "cc: fetching from origin..."
    git -C "$source_repo" fetch origin 2>/dev/null || true

    local branch_exists=false
    # Check local branch
    if git -C "$source_repo" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        branch_exists=true
    fi
    # Check remote branch
    if git -C "$source_repo" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
        branch_exists=true
    fi

    if $branch_exists; then
        git -C "$source_repo" worktree add "$wt_dest" "$branch" || return 1
    else
        echo "cc: branch '$branch' not found — creating from current HEAD"
        git -C "$source_repo" worktree add -b "$branch" "$wt_dest" || return 1
    fi

    echo "cc: worktree ready → $wt_dest"
    cd "$wt_dest"

    # Start Claude session (prompt for cleanup on exit)
    claude "$@"

    # After session ends, offer to remove worktree
    echo ""
    echo -n "cc: Remove this worktree? ($wt_dest) [y/N] "
    read -r _cc_answer
    if [[ "$_cc_answer" == "y" || "$_cc_answer" == "Y" ]]; then
        cd "$source_repo"
        git worktree remove "$wt_dest" && echo "cc: worktree removed."
    else
        echo "cc: worktree kept. To remove later: cc clean"
        echo "    or: git -C \"$source_repo\" worktree remove \"$wt_dest\""
    fi
}

# ──────────────────────────────────────────────────
# cc clean
# ──────────────────────────────────────────────────
_cc_clean() {
    if [[ ! -d "$_CC_WT_BASE" ]]; then
        echo "cc: worktree base directory not found: $_CC_WT_BASE"
        return 0
    fi

    echo "cc: scanning worktrees under $_CC_WT_BASE..."
    echo ""

    local found_any=false
    for project_dir in "$_CC_WT_BASE"/*/; do
        [[ -d "$project_dir" ]] || continue
        local project_name="${project_dir:t}"
        local source_repo="$_CC_PROJECT_BASE/$project_name"

        if [[ ! -d "$source_repo" ]]; then
            echo "  [warning] source repo not found: $source_repo"
            continue
        fi

        echo "  project: $project_name ($source_repo)"
        git -C "$source_repo" worktree list
        echo ""
        found_any=true
    done

    if ! $found_any; then
        echo "cc: no managed worktrees found."
        return 0
    fi

    echo -n "cc: Prune stale worktrees? [y/N] "
    read -r _cc_clean_answer
    if [[ "$_cc_clean_answer" == "y" || "$_cc_clean_answer" == "Y" ]]; then
        for project_dir in "$_CC_WT_BASE"/*/; do
            [[ -d "$project_dir" ]] || continue
            local pname="${project_dir:t}"
            local srepo="$_CC_PROJECT_BASE/$pname"
            [[ -d "$srepo" ]] && git -C "$srepo" worktree prune -v
        done
        echo "cc: prune complete."
    else
        echo "cc: cancelled."
    fi
}

# ──────────────────────────────────────────────────
# cc help
# ──────────────────────────────────────────────────
_cc_help() {
    cat <<EOF
cc — Claude Code wrapper function

Usage:
  cc [claude-opts...]               Start Claude session in current directory
  cc go <path> [claude-opts...]     cd to <path> then start Claude session
  cc wt <branch> [...]              Create (or reuse) worktree from current project, then start Claude
  cc wt <project> <branch> [...]    Create (or reuse) worktree from named project, then start Claude
  cc clean                          List worktrees and prune stale ones
  cc install                        Install/update Claude Code to latest version
  cc help                           Show this help

Subcommand details:

  cc go <path>
    Change to <path> and start a Claude session.
    e.g.  cc go ~/projects/my-app --model opus

  cc wt [<project>] <branch>
    Create a new worktree (or reuse existing) and start Claude.
    Offers to remove the worktree after the session ends.
    Omit <project> to use the current directory's git repository.
    <project> can be an absolute path or a name under \$CC_PROJECT_BASE.
    e.g.  cc wt feature/my-feature
    e.g.  cc wt my-app feature/my-feature
    e.g.  cc wt my-app feature/my-feature --model opus
    e.g.  cc wt ~/projects/my-app fix/issue-123

  cc clean
    Lists all worktrees under \$CC_WT_BASE and runs git worktree prune.

Configuration (export in your .zshrc before sourcing cc.zsh):
  CC_PROJECT_BASE   Base directory for projects  (default: ~/projects)
  CC_WT_BASE        Base directory for worktrees (default: ~/worktrees)

Current config:
  CC_PROJECT_BASE = $_CC_PROJECT_BASE
  CC_WT_BASE      = $_CC_WT_BASE
EOF
}

# ──────────────────────────────────────────────────
# Main function
# ──────────────────────────────────────────────────
cc() {
    case "$1" in
        go)      shift; _cc_go "$@" ;;
        wt)      shift; _cc_worktree "$@" ;;
        clean)   _cc_clean ;;
        install) curl -fsSL https://claude.ai/install.sh | bash ;;
        help)    _cc_help ;;
        *)       claude "$@" ;;
    esac
}
