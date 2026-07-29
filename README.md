# cc — Claude Code wrapper for zsh

A lightweight zsh wrapper around [Claude Code CLI](https://claude.ai/code) that adds **worktree-based branch isolation**, project navigation, and session cleanup — without replacing the native `claude` command.

---

## Features

| Command | Description |
|---------|-------------|
| `cc [opts...]` | Start Claude in the current directory (passthrough to `claude`) |
| `cc go <path>` | `cd` to a path and start Claude |
| `cc wt <branch>` | Create (or reuse) a git worktree and start Claude there |
| `cc wt <project> <branch>` | Same, but for a named project under `$CC_PROJECT_BASE` |
| `cc clean` | List managed worktrees and prune stale ones |
| `cc doctor [--no-probe]` | Diagnose the agent-teams environment |
| `cc reload` | Re-source `cc.zsh` into the current shell |
| `cc install` | Install / update Claude Code to latest |
| `cc help` | Show inline help with current config paths |

### Flags

These are consumed by `cc` and expanded before the rest is passed to `claude`. They combine with any subcommand — e.g. `cc go ~/projects/my-app --teams`.

| Flag | Expands to |
|------|-----------|
| `--teams` | Launches via `cmux claude-teams` instead of `claude`, enabling agent teams so every **named** teammate opens in its own split pane. Also appends `--permission-mode default` unless you pass a `--permission-mode` of your own — teammates are never spawned while the session is in plan mode, so inheriting `permissions.defaultMode: plan` would leave a teams session unable to do the one thing it was launched for. Shorthand alias: `cct` |
| `--discord` | `--channels plugin:discord@claude-plugins-official` |

---

## Why not just use `claude -w`?

`claude --add-dir` / `-w` lets Claude *read* another directory, but you're still working in one repository context. `cc wt` creates a real **git worktree** — an independent checkout of a branch — so Claude operates in a completely isolated working directory. This means:

| | `claude -w` | `cc wt` |
|---|---|---|
| Isolation | Shared working tree | Separate checkout per branch |
| Branch switching | Manual | Automatic (creates if missing) |
| Parallel sessions | Risk of cross-branch edits | Safe — each worktree is independent |
| Cleanup | n/a | Prompted on session exit |
| Existing worktree reuse | n/a | Automatically reuses if present |

---

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash
```

Installs to `~/.config/zsh/claude-cc/` and adds a `source` line to `~/.zshrc`.

### Oh My Zsh

```bash
git clone --depth 1 https://github.com/Ahngbeom/claude-cc.git \
  "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cc"
```

Then add `cc` to your `plugins` list in `~/.zshrc`:

```zsh
plugins=(... cc)
```

### Manual

```bash
git clone --depth 1 https://github.com/Ahngbeom/claude-cc.git ~/.config/zsh/claude-cc
echo 'source ~/.config/zsh/claude-cc/cc.zsh' >> ~/.zshrc
source ~/.zshrc
```

---

## Configuration

Set these **before** sourcing `cc.zsh` (e.g. in `~/.zshrc`):

```zsh
export CC_PROJECT_BASE="$HOME/projects"    # where your repos live (default: ~/projects)
export CC_WT_BASE="$HOME/worktrees"        # where worktrees are created (default: ~/worktrees)

source ~/.config/zsh/claude-cc/cc.zsh
```

`cc help` always shows the currently active values.

`cc.zsh` also exports **`CC_SELF`** — the path to the file it was sourced from. `cc reload` and the self-repair path in `cc()` use it to find themselves again. You don't need to set it; do so only if `cc.zsh` is loaded in a way that hides its own path (e.g. via `eval`).

---

## Usage examples

```zsh
# Start Claude in the current directory (identical to running `claude`)
cc

# Open a project directory
cc go ~/projects/my-app

# Create a worktree for a new feature branch (run from inside a git repo)
cc wt feature/my-feature

# Create a worktree for a specific project by name
cc wt my-app feature/my-feature

# Use an absolute path as the project source
cc wt ~/projects/my-app fix/issue-123

# Pass Claude options through
cc wt my-app feature/my-feature --model opus

# List all managed worktrees and optionally prune them
cc clean

# Start a session with agent teams (named teammates get their own split panes)
cct                          # same as: cc --teams  (adds --permission-mode default)
cct --permission-mode plan   # opt out of that override
cc wt feature/my-feature --teams

# Check why agent teams isn't behaving; exit code = number of failures
cc doctor
cc doctor --no-probe         # skip the live cmux probe
```

### Worktree lifecycle

```
cc wt my-app feature/my-feature
  ↓  fetches origin
  ↓  creates ~/worktrees/my-app/feature/my-feature  (or reuses if it exists)
  ↓  cd into worktree
  ↓  starts claude
  ↓  [you work in Claude...]
  ↓  claude exits
  ↓  "Remove this worktree? [y/N]"
```

---

## Updating

```bash
# If installed via one-liner or manual git clone:
git -C ~/.config/zsh/claude-cc pull

# Or re-run the installer:
curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash
```

`cc` is a shell function, so pulling a new version does **not** affect shells that already
loaded it — they keep running the old definition. Run `cc reload` in each open shell, or just
start a new one. `cc doctor` reports this situation as stale.

---

## Requirements

- **zsh** (tested on zsh 5.9+)
- **git** (for worktree commands)
- **Claude Code CLI** — install with `cc install` or follow [official docs](https://claude.ai/code)
- **cmux CLI** — only for `--teams` / `cct`; `cc doctor` also uses it for its live probe. Everything else works without it.

---

## License

MIT — see [LICENSE](./LICENSE)

---

<details>
<summary>한국어 설명</summary>

## cc — Claude Code zsh 래퍼

Claude Code CLI를 감싸는 경량 zsh 함수입니다. **git worktree 기반 브랜치 격리**, 프로젝트 이동, 세션 정리 기능을 추가합니다.

### 설치

```bash
curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash
```

### 설정

`~/.zshrc`에서 `cc.zsh`를 source하기 전에 환경변수를 설정합니다:

```zsh
export CC_PROJECT_BASE="$HOME/Flyingdoctor"   # 프로젝트 루트
export CC_WT_BASE="$HOME/Flyingdoctor/worktrees"  # worktree 저장 위치

source ~/.config/zsh/claude-cc/cc.zsh
```

### 주요 커맨드

| 커맨드 | 설명 |
|--------|------|
| `cc` | 현재 디렉토리에서 Claude 세션 시작 |
| `cc go <경로>` | 경로로 이동 후 Claude 시작 |
| `cc wt <브랜치>` | Worktree 생성(또는 재사용) 후 Claude 시작 |
| `cc wt <프로젝트> <브랜치>` | 지정 프로젝트에서 Worktree 생성 |
| `cc clean` | Worktree 목록 확인 및 prune |
| `cc doctor [--no-probe]` | agent teams 환경 진단 (종료코드 = 실패 개수) |
| `cc reload` | 현재 셸에 `cc.zsh`를 다시 읽어들임 |
| `cc help` | 도움말 및 현재 설정 경로 출력 |

`cc help`를 실행하면 현재 `CC_PROJECT_BASE`, `CC_WT_BASE` 값을 확인할 수 있습니다.

### 전용 플래그

`cc`가 먼저 해석한 뒤 나머지를 `claude`에 넘깁니다. 모든 서브커맨드와 조합됩니다 (예: `cc go ~/projects/my-app --teams`).

| 플래그 | 동작 |
|--------|------|
| `--teams` | `claude` 대신 `cmux claude-teams`로 실행합니다. agent teams가 켜지고 **이름이 붙은** 팀원이 각자 분할 페인에서 열립니다. `--permission-mode`를 직접 주지 않으면 `--permission-mode default`도 함께 붙습니다 — plan 모드에서는 팀원이 생성되지 않으므로, `permissions.defaultMode: plan`을 그대로 물려받으면 teams 세션이 정작 아무것도 못 합니다. 해제하려면 `cct --permission-mode plan`. 축약 별칭: `cct` |
| `--discord` | `--channels plugin:discord@claude-plugins-official` 로 확장됩니다 |

`--teams`와 `cc doctor`의 live probe는 **cmux CLI**가 필요합니다. 나머지 기능은 없어도 동작합니다.

### 새 버전 반영

`cc`는 셸 함수라서 `git pull`을 해도 **이미 로드된 셸에는 반영되지 않습니다.** 열려 있는 셸에서 `cc reload`를 실행하거나 새 셸을 여세요. `cc doctor`가 이 상태를 stale로 보고합니다.

</details>
