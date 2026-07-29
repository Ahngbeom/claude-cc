# cc — Claude Code wrapper function
# Subcommands: go, wt, clean, doctor, reload, install, help
# All other arguments are passed directly to claude (preserves original alias behavior)
#
# 내부 헬퍼는 __cc_* / __CC_* 로 명명한다. 싱글 언더스코어는 zsh 컴플리션 시스템의
# 네임스페이스이고, Claude Code의 shell snapshot이 그것을 걸러내기 때문이다 (cc() 참조).
#
# Configuration (set in your .zshrc before sourcing this file):
#   export CC_PROJECT_BASE="$HOME/projects"   # default: ~/projects
#   export CC_WT_BASE="$HOME/worktrees"       # default: ~/worktrees

__CC_WT_BASE="${CC_WT_BASE:-$HOME/worktrees}"
__CC_PROJECT_BASE="${CC_PROJECT_BASE:-$HOME/projects}"

# 세션을 실제로 띄우는 커맨드. --teams가 주어지면 cmux claude-teams로 교체된다.
__cc_launcher=(claude)

# 파일 mtime (epoch). BSD(macOS) 우선, 실패하면 GNU.
__cc_mtime() {
    [[ -r "$1" ]] || return 1
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# PATH에서 디렉터리의 1-based 순번. 없으면 0.
# 존재 여부가 아니라 순번이 필요한 이유: 같은 이름의 shim이 둘 이상 올라왔을 때
# 실제로 실행되는 건 앞선 쪽이고, 그게 진단에서 알고 싶은 정보다.
__cc_path_index() {
    local dir="$1" i=1 e
    for e in ${(s.:.)PATH}; do
        [[ "$e" == "$dir" ]] && { print -r -- $i; return }
        (( i++ ))
    done
    print -r -- 0
}

# 이 파일 자신의 경로와 로드 시각.
# cc는 셸 함수라 한 번 로드되면 파일을 고쳐도 기존 셸에는 반영되지 않는다.
# cc doctor의 stale 감지, cc reload, 그리고 cc()의 자가 복구가 이 값을 쓴다.
# zsh에서 sourced 파일 내부의 $0은 그 파일 경로다 (cc.plugin.zsh와 같은 관용구).
# eval로 로드되는 등 경로를 알 수 없는 경우 두 값 모두 비어 있고, 관련 기능은 조용히 꺼진다.
#
# CC_SELF만 export한다. 셸 변수는 프로세스 경계를 넘지 못하므로, 헬퍼를 잃은 채
# 시작된 자식 셸(cc() 상단 주석 참조)이 스스로를 복구하려면 이 경로가 환경으로
# 전달되어야 한다. 반대로 __CC_LOADED_MTIME은 export하면 안 된다 — 파일을 새로
# 읽은 자식이 부모의 로드 시각을 물려받아 stale 판정이 거꾸로 뒤집힌다.
CC_SELF="${0:A}"
[[ -r "$CC_SELF" ]] || CC_SELF=""
export CC_SELF
__CC_LOADED_MTIME="$(__cc_mtime "$CC_SELF" 2>/dev/null)"

# ──────────────────────────────────────────────────
# __cc_expand_flags: cc 전용 플래그를 claude CLI 옵션으로 변환
# 결과는 __cc_args 배열에, 런처는 __cc_launcher 배열에 저장
# ──────────────────────────────────────────────────
__cc_expand_flags() {
    __cc_args=()
    __cc_launcher=(claude)   # 호출마다 초기화 — 이전 호출의 teams 상태가 새지 않도록
    # teams 여부를 __cc_launcher 내용으로 추론하지 않는다. 런처 형태가 바뀌면
    # 판정이 조용히 깨지므로 별도 플래그로 들고 간다.
    local teams=0 pm_seen=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --teams)   __cc_launcher=(cmux claude-teams); teams=1 ;;
            --discord) __cc_args+=(--channels "plugin:discord@claude-plugins-official") ;;
            --permission-mode)
                # 값까지 같이 넘긴다. 값 누락은 claude의 인자 검증에 맡긴다.
                pm_seen=1
                __cc_args+=("$1")
                if [[ $# -ge 2 ]]; then __cc_args+=("$2"); shift; fi
                ;;
            --permission-mode=*)
                pm_seen=1
                __cc_args+=("$1")
                ;;
            *)         __cc_args+=("$1") ;;
        esac
        shift
    done

    # teams는 plan 모드에서 팀메이트를 띄우지 않는다. settings의
    # permissions.defaultMode(=plan)를 덮되, 사용자가 직접 지정했으면 건드리지 않는다.
    if (( teams && ! pm_seen )); then
        __cc_args+=(--permission-mode default)
    fi
}

# ──────────────────────────────────────────────────
# cc go <path> [claude-opts...]
# ──────────────────────────────────────────────────
__cc_go() {
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

    __cc_expand_flags "$@"
    cd "$target" && "${__cc_launcher[@]}" "${__cc_args[@]}"
}

# ──────────────────────────────────────────────────
# cc wt [<project>] <branch> [claude-opts...]
# ──────────────────────────────────────────────────
__cc_worktree() {
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
            source_repo="$__CC_PROJECT_BASE/$project"
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
    local wt_dest="$__CC_WT_BASE/$project_name/$branch"

    # If worktree already exists, reuse it
    if [[ -d "$wt_dest" ]]; then
        echo "cc: reusing existing worktree: $wt_dest"
        __cc_expand_flags "$@"
        cd "$wt_dest" && "${__cc_launcher[@]}" "${__cc_args[@]}"
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
    __cc_expand_flags "$@"
    "${__cc_launcher[@]}" "${__cc_args[@]}"

    # After session ends, offer to remove worktree
    echo ""
    echo -n "cc: Remove this worktree? ($wt_dest) [y/N] "
    read -r __cc_answer
    if [[ "$__cc_answer" == "y" || "$__cc_answer" == "Y" ]]; then
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
__cc_clean() {
    if [[ ! -d "$__CC_WT_BASE" ]]; then
        echo "cc: worktree base directory not found: $__CC_WT_BASE"
        return 0
    fi

    echo "cc: scanning worktrees under $__CC_WT_BASE..."
    echo ""

    local found_any=false
    for project_dir in "$__CC_WT_BASE"/*/; do
        [[ -d "$project_dir" ]] || continue
        local project_name="${project_dir:t}"
        local source_repo="$__CC_PROJECT_BASE/$project_name"

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
    read -r __cc_clean_answer
    if [[ "$__cc_clean_answer" == "y" || "$__cc_clean_answer" == "Y" ]]; then
        for project_dir in "$__CC_WT_BASE"/*/; do
            [[ -d "$project_dir" ]] || continue
            local pname="${project_dir:t}"
            local srepo="$__CC_PROJECT_BASE/$pname"
            [[ -d "$srepo" ]] && git -C "$srepo" worktree prune -v
        done
        echo "cc: prune complete."
    else
        echo "cc: cancelled."
    fi
}

# ──────────────────────────────────────────────────
# cc doctor — agent teams 환경 진단 (읽기 전용)
#
# 상태 출력 헬퍼. zsh는 동적 스코프이므로 __cc_doctor의 local인
# fails/warns 카운터를 여기서 그대로 증가시킬 수 있다.
# ──────────────────────────────────────────────────
__cc_doctor_ok()   { print -r -- "[OK]   $*" }
__cc_doctor_warn() { print -r -- "[WARN] $*"; (( warns++ )) }
__cc_doctor_fail() { print -r -- "[FAIL] $*"; (( fails++ )) }
__cc_doctor_na()   { print -r -- "[n/a]  $*" }

# epoch → 사람이 읽는 시각. strftime이 없으면 epoch 그대로 노출.
__cc_doctor_time() {
    [[ -n "$1" ]] || { print -r -- "?"; return }
    zmodload -F zsh/datetime b:strftime 2>/dev/null
    if (( ${+builtins[strftime]} )); then
        strftime '%Y-%m-%d %H:%M:%S' "$1"
    else
        print -r -- "epoch $1"
    fi
}

# ──────────────────────────────────────────────────
# __cc_doctor_probe: teams 모드가 실제로 넘기는 환경을 찍어본다.
#
# cmux는 CMUX_CUSTOM_CLAUDE_PATH로 claude 실행 파일을 갈아끼울 수 있다.
# 여기에 env를 출력하는 임시 스크립트를 꽂으면, 인터랙티브 세션을 열거나
# 토큰을 쓰지 않고도 teams 모드의 env를 그대로 관찰할 수 있다.
# 스크립트에는 claude 인자(--teammate-mode auto --append-system-prompt …)가
# 넘어오지만 전부 무시한다.
# ──────────────────────────────────────────────────
__cc_doctor_probe() {
    local probe out rc
    probe="$(mktemp -t cc-doctor-probe)" || return 1
    cat >"$probe" <<'PROBE'
#!/bin/sh
printf 'teams=%s\n'    "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"
printf 'tmux=%s\n'     "${TMUX:-}"
printf 'pane=%s\n'     "${TMUX_PANE:-}"
printf 'termprog=%s\n' "${TERM_PROGRAM:-}"
printf 'tmuxbin=%s\n'  "$(command -v tmux 2>/dev/null)"
PROBE
    chmod +x "$probe"
    if command -v timeout &>/dev/null; then
        out="$(CMUX_CUSTOM_CLAUDE_PATH="$probe" timeout 30 cmux claude-teams 2>&1)"
    else
        out="$(CMUX_CUSTOM_CLAUDE_PATH="$probe" cmux claude-teams 2>&1)"
    fi
    rc=$?
    rm -f "$probe"
    print -r -- "$out"
    return $rc
}

__cc_doctor() {
    local run_probe=1
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-probe) run_probe=0 ;;
            *) echo "cc doctor: unknown option '$1'" >&2; return 2 ;;
        esac
        shift
    done

    local fails=0 warns=0
    local teams_on=0 in_claude=0
    [[ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]] && teams_on=1
    # CLAUDECODE는 claude가 자식 프로세스에 넣는다. 셸 프롬프트에서는 없다.
    [[ -n "${CLAUDECODE:-}" ]] && in_claude=1

    # stale이면 아래 결과 전체가 옛 코드의 산물이므로 맨 앞에서 먼저 알린다.
    print -r -- "── cc.zsh ──"
    local disk_mtime
    disk_mtime="$(__cc_mtime "$CC_SELF" 2>/dev/null)"
    if [[ -z "$__CC_LOADED_MTIME" || -z "$disk_mtime" ]]; then
        __cc_doctor_na "cannot determine cc.zsh version (loaded without a file path?)"
    elif [[ "$disk_mtime" != "$__CC_LOADED_MTIME" ]]; then
        __cc_doctor_warn "stale — this shell loaded cc.zsh at $(__cc_doctor_time "$__CC_LOADED_MTIME"), file changed at $(__cc_doctor_time "$disk_mtime")"
        print -r -- "       Everything below reflects the OLD code. Run: cc reload"
    else
        __cc_doctor_ok "cc.zsh up to date ($CC_SELF)"
    fi

    print -r -- ""
    print -r -- "── cmux ──"
    local cmux_bin
    cmux_bin="$(command -v cmux 2>/dev/null)"
    if [[ -n "$cmux_bin" ]]; then
        __cc_doctor_ok "cmux CLI: $cmux_bin"
    else
        __cc_doctor_fail "cmux CLI not found on PATH — 'cc --teams' / 'cct' cannot work"
    fi

    if [[ -n "${CMUX_SURFACE_ID:-}" ]]; then
        __cc_doctor_ok "inside a cmux surface (workspace ${CMUX_WORKSPACE_ID:-?})"
    else
        __cc_doctor_warn "not inside a cmux surface — teammate splits have nowhere to open"
    fi

    print -r -- ""
    print -r -- "── current session ──"
    if (( in_claude )); then
        # Claude 프로세스 안이므로 teams env가 의미를 갖는다.
        if (( teams_on )); then
            __cc_doctor_ok "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
        else
            __cc_doctor_warn "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS unset — this Claude session has teams OFF"
        fi
        if [[ -n "${TMUX:-}" ]]; then
            __cc_doctor_ok "TMUX=$TMUX (pane ${TMUX_PANE:-<unset>})"
        else
            __cc_doctor_warn "TMUX unset — teammate auto mode has no multiplexer to split"
        fi
        print -r -- "       TERM_PROGRAM=${TERM_PROGRAM:-<unset>}"
        if (( ! teams_on )) && [[ -z "${TMUX:-}" ]]; then
            print -r -- "       → teams: OFF for this session. Start a teams one with: cct"
        fi
    else
        # cmux는 teams env를 자기가 exec하는 claude 프로세스에만 넣는다.
        # 셸에서는 원리상 절대 보이지 않으므로 경고로 세지 않는다.
        __cc_doctor_na "not inside a Claude session — teams env lives in the claude process,"
        print -r -- "       never in the shell that launched it. Nothing to judge from here;"
        print -r -- "       see the live probe below for what teams mode actually sets."
        print -r -- "       TERM_PROGRAM=${TERM_PROGRAM:-<unset>}"
    fi

    print -r -- ""
    print -r -- "── tmux resolution ──"
    local tmux_bin orca_shim="$HOME/.orca/claude-agent-teams-bin/tmux"
    tmux_bin="$(command -v tmux 2>/dev/null)"
    if [[ -z "$tmux_bin" ]]; then
        __cc_doctor_warn "no tmux on PATH"
    elif [[ "$tmux_bin" == (*/cmux-cli-shims/*|*claude-teams-bin*) ]]; then
        # probe 쪽 판정과 같은 기준을 쓴다. cmux는 실행 경로에 따라 shim을
        # $TMPDIR/cmux-cli-shims/ 또는 ~/.cmuxterm/claude-teams-bin/ 아래에 둔다.
        __cc_doctor_ok "tmux → cmux shim: $tmux_bin"
    elif [[ "$tmux_bin" == "$orca_shim" ]]; then
        __cc_doctor_fail "tmux → Orca shim: $tmux_bin (teammate spawns route to Orca, not cmux)"
    elif (( teams_on )); then
        __cc_doctor_fail "tmux → real tmux: $tmux_bin (a teams session should resolve to the cmux shim)"
    else
        __cc_doctor_ok "tmux → real tmux: $tmux_bin (expected outside a teams session)"
    fi

    print -r -- ""
    print -r -- "── coexistence (cmux / Orca) ──"

    # 어느 앱이 이 터미널을 소유하는가. 교차 실행이면 팀메이트 분할이
    # 눈에 보이지 않는 다른 앱의 창으로 간다.
    local in_cmux=0 in_orca=0
    [[ -n "${CMUX_SURFACE_ID:-}" ]] && in_cmux=1
    [[ -n "${ORCA_PANE_KEY:-}${ORCA_WORKTREE_ID:-}" ]] && in_orca=1

    if (( in_cmux && in_orca )); then
        __cc_doctor_warn "terminal reports BOTH cmux and Orca ownership — teammate splits may land in the wrong app"
    elif (( in_cmux )); then
        __cc_doctor_ok "terminal owner: cmux"
    elif (( in_orca )); then
        __cc_doctor_warn "terminal owner: Orca — 'cc --teams' would split into a cmux window not visible here"
    else
        __cc_doctor_ok "terminal owner: neither (plain terminal)"
    fi

    # 두 앱이 agent teams용으로 같은 'tmux' 이름을 선점한다. 평소엔 어느 쪽도
    # PATH에 없어 무해하지만, 둘 다 올라오면 앞선 쪽이 팀메이트 생성을 가져간다.
    local cmux_shim="$HOME/.cmuxterm/claude-teams-bin/tmux"
    local ci oi
    ci=$(__cc_path_index "${cmux_shim:h}")
    oi=$(__cc_path_index "${orca_shim:h}")
    if (( ci && oi )); then
        if (( ci < oi )); then
            __cc_doctor_warn "both teams shims on PATH — cmux wins (position $ci vs Orca $oi)"
        else
            __cc_doctor_warn "both teams shims on PATH — Orca wins (position $oi vs cmux $ci)"
        fi
    elif (( ci )); then
        __cc_doctor_ok "cmux teams shim on PATH (position $ci)"
    elif (( oi )); then
        __cc_doctor_warn "Orca teams shim on PATH (position $oi) — teammate spawns route to Orca"
    else
        __cc_doctor_ok "neither teams shim on PATH (expected outside a teams session)"
    fi
    [[ -e "$cmux_shim" ]] || __cc_doctor_na "cmux teams shim not installed yet: $cmux_shim"
    [[ -e "$orca_shim" ]] || __cc_doctor_na "Orca teams shim not installed: $orca_shim"

    # 같은 레포를 양쪽이 관리하면 'cc wt'가 git의 already-checked-out으로 막히고,
    # 'cc clean'의 prune이 Orca 등록을 건드릴 수 있다.
    if command -v orca &>/dev/null; then
        local orca_out
        if command -v timeout &>/dev/null; then
            orca_out="$(timeout 10 orca worktree list 2>/dev/null)"
        else
            orca_out="$(orca worktree list 2>/dev/null)"
        fi
        if [[ -z "$orca_out" ]]; then
            __cc_doctor_na "orca worktree list returned nothing (Orca not running?)"
        else
            local overlap=0 oline op
            for oline in ${(f)orca_out}; do
                for op in ${=oline}; do
                    case "$op" in
                        "$__CC_WT_BASE"/*|"$__CC_PROJECT_BASE"/*) (( overlap++ )) ;;
                    esac
                done
            done
            if (( overlap )); then
                __cc_doctor_warn "Orca manages $overlap path(s) under CC_PROJECT_BASE/CC_WT_BASE — 'cc wt' and 'cc clean' can collide there"
            else
                __cc_doctor_ok "no Orca worktree under CC_PROJECT_BASE/CC_WT_BASE"
            fi
        fi
    else
        __cc_doctor_na "orca CLI not found — coexistence checks limited to PATH/env"
    fi

    print -r -- ""
    print -r -- "── claude settings ──"
    local settings="$HOME/.claude/settings.json"
    if [[ -r "$settings" ]]; then
        local out tm dm
        out="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("teammateMode","<unset>"));print(d.get("permissions",{}).get("defaultMode","<unset>"))' "$settings" 2>/dev/null)"
        if [[ -z "$out" ]]; then
            __cc_doctor_warn "could not parse $settings (python3 missing or invalid JSON)"
        else
            tm="${out%%$'\n'*}"
            dm="${out##*$'\n'}"
            if [[ "$tm" == auto ]]; then
                __cc_doctor_ok "teammateMode=$tm"
            else
                __cc_doctor_warn "teammateMode=$tm (use \"auto\" so named teammates open their own panes)"
            fi
            if [[ "$dm" == plan ]]; then
                __cc_doctor_warn "permissions.defaultMode=plan — plain 'cc' sessions start read-only"
                print -r -- "       'cc --teams' / 'cct' override it with --permission-mode default,"
                print -r -- "       because teammates are not spawned while in plan mode."
            else
                __cc_doctor_ok "permissions.defaultMode=$dm"
            fi
        fi
    else
        __cc_doctor_warn "settings not readable: $settings"
    fi

    if (( run_probe )); then
        print -r -- ""
        print -r -- "── live probe ──"
        if [[ -z "$cmux_bin" ]]; then
            __cc_doctor_warn "skipped — cmux CLI not available"
        else
            print -r -- "       Running 'cmux claude-teams' with a stand-in for claude to observe"
            print -r -- "       the real teams environment. No session opens, no tokens are spent;"
            print -r -- "       cmux leaves one small dir under \$TMPDIR/cmux-cli-shims/ per run."
            local -A p
            local line key val probe_out
            probe_out="$(__cc_doctor_probe)"
            for line in ${(f)probe_out}; do
                [[ "$line" == *=* ]] || continue
                key="${line%%=*}"
                val="${line#*=}"
                p[$key]="$val"
            done

            if (( ${#p} == 0 )); then
                __cc_doctor_warn "probe produced no readable output:"
                print -r -- "       ${probe_out:-<empty>}"
            else
                if [[ "${p[teams]}" == 1 ]]; then
                    __cc_doctor_ok "teams mode sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
                else
                    __cc_doctor_fail "teams mode did NOT set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS (got '${p[teams]}')"
                fi

                if [[ -n "${p[tmux]}" ]]; then
                    __cc_doctor_ok "teams mode sets TMUX=${p[tmux]} (pane ${p[pane]:-<unset>})"
                else
                    __cc_doctor_fail "teams mode did NOT set TMUX — auto mode has nothing to split"
                fi

                case "${p[tmuxbin]}" in
                    */cmux-cli-shims/*|*claude-teams-bin*)
                        __cc_doctor_ok "tmux resolves to the cmux shim: ${p[tmuxbin]}" ;;
                    "$orca_shim")
                        __cc_doctor_fail "tmux resolves to the Orca shim: ${p[tmuxbin]}" ;;
                    "")
                        __cc_doctor_fail "no tmux on PATH inside teams mode" ;;
                    *)
                        __cc_doctor_fail "tmux resolves to real tmux: ${p[tmuxbin]} (expected the cmux shim)" ;;
                esac
            fi
        fi
    fi

    print -r -- ""
    print -r -- "── notes ──"
    print -r -- "       Teammates spawn via 'tmux split-window … -P -F #{pane_id}'."
    print -r -- "       cmux's shim answers that family (verified: 'tmux list-panes' → %<id>)."
    print -r -- "       The forms cmux rejects — 'new-session -A', 'new-window -t' — are not"
    print -r -- "       used by claude's teammate path, so they are not a concern here."
    print -r -- "       If panes still don't open with a green probe, capture the shim error"
    print -r -- "       and report it against cmux — it is not a cc configuration problem."

    print -r -- ""
    print -r -- "summary: $fails fail, $warns warn"
    return $fails
}

# ──────────────────────────────────────────────────
# cc reload — 현재 셸에 cc.zsh를 다시 읽어들인다.
#
# zsh는 실행 중인 함수의 재정의를 허용한다. 지금 호출은 옛 본문으로 끝나고
# 다음 호출부터 새 정의가 쓰인다. source 이후 echo만 하므로 안전하다.
# source가 CC_SELF/__CC_LOADED_MTIME을 다시 대입하므로 stale 표시도 해소된다.
# ──────────────────────────────────────────────────
__cc_reload() {
    if [[ -z "$CC_SELF" || ! -r "$CC_SELF" ]]; then
        echo "cc: cannot reload — cc.zsh path unknown" >&2
        return 1
    fi
    source "$CC_SELF" && echo "cc: reloaded $CC_SELF"
}

# ──────────────────────────────────────────────────
# cc help
# ──────────────────────────────────────────────────
__cc_help() {
    cat <<EOF
cc — Claude Code wrapper function

Usage:
  cc [claude-opts...]               Start Claude session in current directory
  cc go <path> [claude-opts...]     cd to <path> then start Claude session
  cc wt <branch> [...]              Create (or reuse) worktree from current project, then start Claude
  cc wt <project> <branch> [...]    Create (or reuse) worktree from named project, then start Claude
  cc clean                          List worktrees and prune stale ones
  cc doctor [--no-probe]            Diagnose the agent-teams environment
  cc reload                         Re-source cc.zsh into the current shell
  cc install                        Install/update Claude Code to latest version
  cc help                           Show this help

cc options (expanded before passing to claude):
  --teams                           Launch via 'cmux claude-teams' (agent teams / split-pane teammates)
  --discord                         Enable Discord channel (--channels plugin:discord@claude-plugins-official)

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
    e.g.  cc wt feature/my-feature --teams
    e.g.  cc wt ~/projects/my-app fix/issue-123

  cc clean
    Lists all worktrees under \$CC_WT_BASE and runs git worktree prune.

  cc --teams
    Starts Claude through 'cmux claude-teams', which enables agent teams and
    opens every NAMED teammate in its own cmux split pane. Requires the cmux
    CLI, and works best from inside a cmux surface. Combines with the other
    subcommands, e.g. 'cc go ~/projects/my-app --teams'.
    Shorthand alias: cct

    Adds --permission-mode default unless you pass a --permission-mode yourself.
    Teammates are not spawned while in plan mode, and this machine's
    permissions.defaultMode is 'plan', so without the override a teams session
    would start unable to do the very thing it was launched for.
    To opt out:  cct --permission-mode plan

  cc doctor [--no-probe]
    Checks everything agent teams depends on: the cmux CLI, whether this shell is
    a cmux surface, which tmux the PATH resolves to (cmux shim vs Orca shim vs
    real tmux), and the relevant ~/.claude/settings.json keys.

    It also reports coexistence with Orca, which ships a competing agent-teams
    tmux shim: who owns this terminal, which of the two shims wins on PATH, and
    whether Orca manages any worktree under CC_PROJECT_BASE / CC_WT_BASE (where
    'cc wt' and 'cc clean' would collide with it).

    The teams env vars (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS, TMUX) only exist
    inside the claude process cmux spawns, never in the shell that launched it.
    So doctor runs a live probe: it swaps in a stand-in for claude via
    CMUX_CUSTOM_CLAUDE_PATH and reports the environment teams mode actually
    hands over. No session opens and no tokens are spent, but cmux leaves one
    small dir under \$TMPDIR/cmux-cli-shims/ per run. Pass --no-probe to skip it.

    Exit code = number of failures.

  cc reload
    Re-sources cc.zsh into the current shell. cc is a shell function, so editing
    the file (or pulling a new version) does NOT affect shells that already
    loaded it — they keep running the old definition. 'cc doctor' flags that
    situation as stale; this is the fix, without restarting the shell.

Configuration (export in your .zshrc before sourcing cc.zsh):
  CC_PROJECT_BASE   Base directory for projects  (default: ~/projects)
  CC_WT_BASE        Base directory for worktrees (default: ~/worktrees)

Current config:
  CC_PROJECT_BASE = $__CC_PROJECT_BASE
  CC_WT_BASE      = $__CC_WT_BASE
EOF
}

# ──────────────────────────────────────────────────
# Main function
# ──────────────────────────────────────────────────
cc() {
    # 헬퍼가 통째로 사라진 셸에서 스스로를 복구한다.
    #
    # Claude Code는 Bash 도구용 셸을 .zshrc 재실행이 아니라 shell snapshot
    # (~/.claude/shell-snapshots/)으로 초기화하는데, 그 스냅샷은 zsh 컴플리션
    # 함수(_git, _docker …) 수천 개를 걸러내려고 싱글 언더스코어로 시작하는
    # 함수를 제외한다. 헬퍼가 __cc_* (더블 언더스코어)인 것은 이 필터를 통과하기
    # 위해서다. 그래도 스냅샷 구현은 우리 소관이 아니므로, 규칙이 바뀌어 다시
    # 유실되더라도 cc가 조용히 오작동하지 않도록 여기서 한 겹 더 받친다.
    if ! typeset -f __cc_expand_flags >/dev/null 2>&1; then
        local __cc_src
        for __cc_src in "$CC_SELF" "$HOME/.config/zsh/claude-cc/cc.zsh"; do
            [[ -n "$__cc_src" && -r "$__cc_src" ]] && source "$__cc_src" && break
        done
        if ! typeset -f __cc_expand_flags >/dev/null 2>&1; then
            echo "cc: helper functions are missing and cc.zsh could not be re-sourced" >&2
            echo "    export CC_SELF=/path/to/cc.zsh, or source it manually" >&2
            return 1
        fi
    fi

    # --teams는 세션을 띄우기 직전이 아니라 여기서 먼저 검증한다.
    # __cc_worktree는 worktree를 만든 뒤에 런처를 실행하므로, 그때 실패하면 늦다.
    if [[ "$*" == *--teams* ]]; then
        if ! command -v cmux &>/dev/null; then
            echo "cc: --teams requires the cmux CLI (not found on PATH)" >&2
            echo "    install cmux, or drop --teams to run plain claude" >&2
            return 1
        fi
        if [[ -z "${CMUX_SURFACE_ID:-}" ]]; then
            if [[ -n "${ORCA_PANE_KEY:-}${ORCA_WORKTREE_ID:-}" ]]; then
                # 두 앱이 agent teams용으로 같은 'tmux' 이름을 쓴다. cmux가 자기 shim을
                # PATH 앞에 붙이므로 Orca 터미널에서 실행해도 cmux가 이기고, 분할은
                # 이 창이 아닌 cmux 쪽에 열린다. 막지는 않는다 — 의도적인 경우도 있다.
                echo "cc: this is an Orca-managed terminal, not a cmux surface." >&2
                echo "    --teams still runs, but cmux puts its own tmux shim ahead of Orca's," >&2
                echo "    so teammate panes open in a cmux window you cannot see from here." >&2
                echo "    Run it from a cmux pane instead." >&2
            else
                echo "cc: warning — not inside a cmux surface; teammate splits may not appear" >&2
            fi
        fi
    fi

    case "$1" in
        go)      shift; __cc_go "$@" ;;
        wt)      shift; __cc_worktree "$@" ;;
        clean)   __cc_clean ;;
        doctor)  shift; __cc_doctor "$@" ;;
        reload)  __cc_reload ;;
        install) curl -fsSL https://claude.ai/install.sh | bash ;;
        help)    __cc_help ;;
        *)       __cc_expand_flags "$@"; "${__cc_launcher[@]}" "${__cc_args[@]}" ;;
    esac
}
