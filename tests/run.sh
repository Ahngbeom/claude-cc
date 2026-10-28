#!/usr/bin/env bash
# cc test suite. Runs every case once per shell, through that shell's shim.
#
# Usage: tests/run.sh [zsh] [bash]
#   With no arguments, every shell whose shim exists and binary is installed.
#   TEST_ZSH / TEST_BASH pin the interpreter binaries. TEST_BASH also becomes
#   the `bash` that bin/claude-cc's shebang resolves to (e.g. macOS /bin/bash 3.2).
#
# Real claude, cmux and orca are never run: PATH directories that contain them
# are dropped, and stubs stand in. HOME and git config are sandboxed per shell.
#
# Keep this file bash 3.2 compatible — it runs under TEST_BASH too.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
pass=0
fail=0

# ── assertions ───────────────────────────────────
bad() {
    fail=$((fail + 1))
    printf '  FAIL [%s] %s\n' "$SH_NAME" "$1"
    [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/       | /'
}
expect_eq() {
    if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); else bad "$1: expected [$3], got [$2]"; fi
}
expect_contains() {
    case "$2" in
        *"$3"*) pass=$((pass + 1)) ;;
        *) bad "$1: expected output to contain [$3]" "$2" ;;
    esac
}
expect_not_contains() {
    case "$2" in
        *"$3"*) bad "$1: expected output NOT to contain [$3]" "$2" ;;
        *) pass=$((pass + 1)) ;;
    esac
}
expect_line() {
    if printf '%s\n' "$2" | grep -Fqx -- "$3"; then pass=$((pass + 1)); else bad "$1: expected a line [$3]" "$2"; fi
}
expect_dir() {
    if [[ -d "$2" ]]; then pass=$((pass + 1)); else bad "$1: expected directory $2"; fi
}
expect_no_dir() {
    if [[ ! -d "$2" ]]; then pass=$((pass + 1)); else bad "$1: expected no directory $2"; fi
}

# ── sandbox ──────────────────────────────────────
clean_path() {
    local out='' d IFS=:
    for d in $PATH; do
        [[ -n "$d" ]] || continue
        [[ -e "$d/claude" || -e "$d/cmux" || -e "$d/orca" ]] && continue
        out="${out:+$out:}$d"
    done
    printf '%s' "$out"
}

setup_sandbox() {
    SB="$(mktemp -d "${TMPDIR:-/tmp}/cc-test.XXXXXX")" || exit 1
    SB="$(CDPATH='' cd -- "$SB" && pwd -P)"
    mkdir -p "$SB/home/.claude" "$SB/stubs" "$SB/cmuxbin" "$SB/interp" "$SB/projects" \
        "$SB/cmux-cli-shims/run1"

    printf '{"teammateMode":"auto","permissions":{"defaultMode":"default"}}\n' \
        >"$SB/home/.claude/settings.json"

    cat >"$SB/stubs/claude" <<'EOF'
#!/bin/sh
printf 'FAKE-CLAUDE cwd=%s\n' "$(pwd -P)"
for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
exit "${FAKE_CLAUDE_RC:-0}"
EOF

    # Mirrors what cmux claude-teams hands its claude: teams env, TMUX, and a
    # tmux shim under a cmux-cli-shims/ dir. CMUX_CUSTOM_CLAUDE_PATH swaps claude.
    cat >"$SB/cmuxbin/cmux" <<EOF
#!/bin/sh
[ "\$1" = claude-teams ] || { echo "fake cmux: unsupported: \$*" >&2; exit 2; }
shift
if [ -n "\$CMUX_CUSTOM_CLAUDE_PATH" ]; then
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 TMUX=/tmp/fake-cmux,1,0 TMUX_PANE=%1 \\
        PATH="$SB/cmux-cli-shims/run1:\$PATH" exec "\$CMUX_CUSTOM_CLAUDE_PATH" "\$@"
fi
printf 'FAKE-CMUX\n'
for a in "\$@"; do printf 'arg=[%s]\n' "\$a"; done
EOF
    printf '#!/bin/sh\nexit 0\n' >"$SB/cmux-cli-shims/run1/tmux"
    chmod +x "$SB/stubs/claude" "$SB/cmuxbin/cmux" "$SB/cmux-cli-shims/run1/tmux"

    [[ -n "${TEST_BASH:-}" ]] && ln -s "$TEST_BASH" "$SB/interp/bash"

    export HOME="$SB/home"
    export PATH="$SB/interp:$SB/stubs:$BASE_PATH"
    export CC_PROJECT_BASE="$SB/projects"
    export CC_WT_BASE="$SB/worktrees"

    git init -q --bare "$SB/origin.git"
    git init -q "$SB/projects/demo"
    git -C "$SB/projects/demo" commit -q --allow-empty -m init
    git -C "$SB/projects/demo" remote add origin "$SB/origin.git"
    git -C "$SB/projects/demo" push -q origin HEAD:refs/heads/main HEAD:refs/heads/remote-only
    git init -q "$HOME/tilde-repo"
    git -C "$HOME/tilde-repo" commit -q --allow-empty -m init
    mkdir -p "$SB/projects/notrepo"
}

# run_in <dir> <stdin> <cc args...> → OUT (stdout+stderr), RC
run_in() {
    local dir="$1" input="$2"
    shift 2
    OUT="$(printf '%s' "$input" | "$SH_BIN" "${SH_FLAGS[@]}" -c \
        'cd "$1" || exit 99; source "$2"; shift 2; cc "$@"' cc-test "$dir" "$SHIM" "$@" 2>&1)"
    RC=$?
}

with_cmux() { PATH="$SB/cmuxbin:$PATH" CMUX_SURFACE_ID=test "$@"; }

branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null; }

# ── cases ────────────────────────────────────────
test_passthrough() {
    run_in "$SB" "" --discord -x
    expect_eq "bare cc rc" "$RC" 0
    expect_line "bare cc runs in cwd" "$OUT" "FAKE-CLAUDE cwd=$SB"
    expect_contains "--discord expands, other args pass through" "$OUT" \
        "arg=[--channels]
arg=[plugin:discord@claude-plugins-official]
arg=[-x]"

    export FAKE_CLAUDE_RC=7
    run_in "$SB" ""
    unset FAKE_CLAUDE_RC
    expect_eq "claude exit code propagates" "$RC" 7
}

test_teams() {
    run_in "$SB" "" --teams
    expect_eq "--teams without cmux rc" "$RC" 1
    expect_contains "--teams without cmux explains" "$OUT" "requires the cmux CLI"
    expect_not_contains "--teams without cmux does not start claude" "$OUT" "FAKE-CLAUDE"

    with_cmux run_in "$SB" "" --teams
    expect_line "--teams launches through cmux" "$OUT" "FAKE-CMUX"
    expect_contains "--teams adds --permission-mode default" "$OUT" \
        "arg=[--permission-mode]
arg=[default]"

    with_cmux run_in "$SB" "" --teams --permission-mode plan
    expect_contains "explicit --permission-mode is kept" "$OUT" "arg=[plan]"
    expect_not_contains "explicit --permission-mode is not overridden" "$OUT" "arg=[default]"

    with_cmux run_in "$SB" "" --teams --permission-mode=plan
    expect_not_contains "--permission-mode=VALUE is not overridden" "$OUT" "arg=[default]"
}

test_go() {
    run_in "$SB" "" go "$SB/projects/demo" --model opus
    expect_eq "go rc" "$RC" 0
    expect_line "go runs claude in target" "$OUT" "FAKE-CLAUDE cwd=$SB/projects/demo"
    expect_contains "go passes options" "$OUT" "arg=[--model]
arg=[opus]"

    run_in "$SB" "" go "$SB/nope"
    expect_eq "go missing path rc" "$RC" 1
    expect_contains "go missing path message" "$OUT" "path not found"

    run_in "$SB" "" go
    expect_eq "go without args rc" "$RC" 1
    expect_contains "go without args usage" "$OUT" "Usage: cc go"
}

test_clean_without_base() {
    run_in "$SB" "" clean
    expect_eq "clean without base rc" "$RC" 0
    expect_contains "clean without base message" "$OUT" "worktree base directory not found"
}

test_wt() {
    local wt="$SB/worktrees/demo"

    run_in "$SB" $'n\n' wt demo feature/x --model opus
    expect_line "wt creates and starts claude there" "$OUT" "FAKE-CLAUDE cwd=$wt/feature/x"
    expect_contains "wt passes options" "$OUT" "arg=[--model]
arg=[opus]"
    expect_contains "wt keeps on 'n'" "$OUT" "worktree kept"
    expect_eq "wt creates the branch" "$(branch_of "$wt/feature/x")" feature/x

    run_in "$SB" $'n\n' wt demo feature/x
    expect_contains "wt reuses an existing worktree" "$OUT" "reusing existing worktree"
    expect_line "wt reuse starts claude there" "$OUT" "FAKE-CLAUDE cwd=$wt/feature/x"

    run_in "$SB" $'y\n' wt demo feature/y
    expect_contains "wt removes on 'y'" "$OUT" "worktree removed."
    expect_no_dir "wt removed directory" "$wt/feature/y"

    run_in "$SB/projects/demo" $'n\n' wt feature/z --model opus
    expect_line "wt <branch> uses the current repo" "$OUT" "FAKE-CLAUDE cwd=$wt/feature/z"
    expect_contains "wt <branch> passes options" "$OUT" "arg=[--model]"

    run_in "$SB" $'n\n' wt "$SB/projects/demo" abs/b
    expect_line "wt accepts an absolute project path" "$OUT" "FAKE-CLAUDE cwd=$wt/abs/b"

    run_in "$SB" $'n\n' wt demo remote-only
    expect_eq "wt checks out a remote-only branch" "$(branch_of "$wt/remote-only")" remote-only

    # shellcheck disable=SC2088
    run_in "$SB" $'n\n' wt '~/tilde-repo' t/b
    expect_line "wt expands a quoted ~ project path" "$OUT" \
        "FAKE-CLAUDE cwd=$SB/worktrees/tilde-repo/t/b"

    run_in "$SB" "" wt notrepo b
    expect_eq "wt on a non-repo rc" "$RC" 1
    expect_contains "wt on a non-repo message" "$OUT" "not a git repository"

    run_in "$SB" "" wt demo feature/t --teams
    expect_eq "wt --teams without cmux rc" "$RC" 1
    expect_no_dir "wt --teams without cmux creates nothing" "$wt/feature/t"
}

test_unexported_config() {
    OUT="$(printf 'n\n' | env -u CC_WT_BASE "$SH_BIN" "${SH_FLAGS[@]}" -c \
        'CC_WT_BASE="$1"; source "$2"; cc wt demo un/exported' cc-test "$SB/alt-wt" "$SHIM" 2>&1)"
    expect_line "an unexported CC_WT_BASE shell variable is honored" "$OUT" \
        "FAKE-CLAUDE cwd=$SB/alt-wt/demo/un/exported"
}

test_clean() {
    run_in "$SB" $'n\n' clean
    expect_contains "clean lists managed worktrees" "$OUT" "project: demo"
    expect_contains "clean cancels on 'n'" "$OUT" "cancelled"

    run_in "$SB" $'y\n' clean
    expect_contains "clean prunes on 'y'" "$OUT" "prune complete"
}

test_doctor() {
    local fails
    run_in "$SB" "" doctor --no-probe
    fails="$(printf '%s\n' "$OUT" | grep -c '^\[FAIL\]')"
    expect_eq "doctor exit code = number of failures" "$RC" "$fails"
    expect_contains "doctor reads settings" "$OUT" "[OK]   teammateMode=auto"
    expect_contains "doctor outside claude" "$OUT" "not inside a Claude session"

    export CLAUDECODE=1
    run_in "$SB" "" doctor --no-probe
    unset CLAUDECODE
    expect_contains "doctor inside claude judges teams env" "$OUT" \
        "[WARN] CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS unset"

    run_in "$SB" "" doctor --bogus
    expect_eq "doctor unknown option rc" "$RC" 2
}

test_help() {
    run_in "$SB" "" help
    expect_contains "help shows usage" "$OUT" "Usage:"
    expect_contains "help shows current config" "$OUT" "CC_WT_BASE      = $SB/worktrees"
}

# Claude Code starts its Bash tool from a shell snapshot: function bodies and
# env survive, but nothing else from the rc file is re-run.
test_snapshot_shell() {
    local defs snap
    defs="$("$SH_BIN" "${SH_FLAGS[@]}" -c 'source "$1"; typeset -f cc' cc-test "$SHIM")"
    snap="$("$SH_BIN" "${SH_FLAGS[@]}" -c 'source "$1"; printf "%s\n%s" "$PATH" "${CC_SELF:-}"' cc-test "$SHIM")"
    OUT="$(PATH="${snap%%$'\n'*}" CC_SELF="${snap#*$'\n'}" "$SH_BIN" "${SH_FLAGS[@]}" -c \
        'eval "$1"; shift; cc "$@"' cc-test "$defs" doctor --no-probe 2>&1)"
    expect_contains "cc works from a snapshot shell" "$OUT" "── claude settings ──"
}

test_cct() {
    OUT="$(PATH="$SB/cmuxbin:$PATH" CMUX_SURFACE_ID=test "$SH_BIN" "${SH_FLAGS[@]}" -c \
        'source "$1"; shift; cct "$@"' cc-test "$SHIM" --model opus 2>&1)"
    expect_line "cct launches through cmux" "$OUT" "FAKE-CMUX"
    expect_contains "cct passes options and adds the permission mode" "$OUT" \
        "arg=[--model]
arg=[opus]
arg=[--permission-mode]
arg=[default]"
}

test_reload() {
    run_in "$SB" "" reload
    expect_eq "reload rc" "$RC" 0
    expect_contains "reload says it is no longer needed" "$OUT" "no longer needed"
}

test_doctor_probe() {
    with_cmux run_in "$SB" "" doctor
    expect_contains "probe sees the teams env" "$OUT" \
        "[OK]   teams mode sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
    expect_contains "probe sees TMUX" "$OUT" "[OK]   teams mode sets TMUX=/tmp/fake-cmux,1,0 (pane %1)"
    expect_contains "probe sees the cmux tmux shim" "$OUT" \
        "[OK]   tmux resolves to the cmux shim: $SB/cmux-cli-shims/run1/tmux"
}

test_doctor_version() {
    run_in "$SB" "" doctor --no-probe
    expect_contains "doctor reports the claude-cc it runs" "$OUT" "$ROOT/bin/claude-cc"
    expect_not_contains "doctor has no stale check" "$OUT" "stale"
}

# ── driver ───────────────────────────────────────
for v in CLAUDECODE CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS TMUX TMUX_PANE CMUX_SURFACE_ID \
    CMUX_WORKSPACE_ID ORCA_PANE_KEY ORCA_WORKTREE_ID CC_PROJECT_BASE CC_WT_BASE CC_SELF \
    BASH_ENV ENV ZDOTDIR CDPATH FAKE_CLAUDE_RC; do
    unset "$v"
done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=cc-test GIT_AUTHOR_EMAIL=cc-test@example.com \
    GIT_COMMITTER_NAME=cc-test GIT_COMMITTER_EMAIL=cc-test@example.com
BASE_PATH="$(clean_path)"
ORIG_HOME="$HOME"
ORIG_PATH="$PATH"

if [[ $# -gt 0 ]]; then shells=("$@"); explicit=1; else shells=(zsh bash); explicit=0; fi

for SH_NAME in "${shells[@]}"; do
    case "$SH_NAME" in
        zsh)  SHIM="$ROOT/cc.zsh";  SH_FLAGS=(-f);                  SH_BIN="${TEST_ZSH:-}" ;;
        bash) SHIM="$ROOT/cc.bash"; SH_FLAGS=(--norc --noprofile); SH_BIN="${TEST_BASH:-}" ;;
        *) echo "unknown shell: $SH_NAME" >&2; exit 2 ;;
    esac
    [[ -n "$SH_BIN" ]] || SH_BIN="$(PATH="$ORIG_PATH" command -v "$SH_NAME")"
    if [[ ! -r "$SHIM" || -z "$SH_BIN" ]]; then
        if (( explicit )); then bad "$SH_NAME requested but shim or binary is missing"; fi
        printf 'skip %s\n' "$SH_NAME"
        continue
    fi

    printf '── %s (%s) ──\n' "$SH_NAME" "$SH_BIN"
    before=$fail
    setup_sandbox
    test_passthrough
    test_teams
    test_go
    test_clean_without_base
    test_wt
    test_unexported_config
    test_clean
    test_doctor
    test_help
    test_snapshot_shell
    test_cct
    test_reload
    test_doctor_probe
    test_doctor_version
    (( fail == before )) && rm -rf "$SB" || printf '  sandbox kept: %s\n' "$SB"
    export HOME="$ORIG_HOME" PATH="$ORIG_PATH"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
