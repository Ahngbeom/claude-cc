# cc — Claude Code wrapper for zsh

A lightweight wrapper around [Claude Code CLI](https://claude.ai/code) for **zsh and bash** that adds **worktree-based branch isolation**, project navigation, and session cleanup — without replacing the native `claude` command.

---

## Features

| Command | Description |
|---------|-------------|
| `cc [opts...]` | Start Claude in the current directory (passthrough to `claude`) |
| `cc go <path>` | Start Claude in a path |
| `cc wt <branch>` | Create (or reuse) a git worktree and start Claude there |
| `cc wt <project> <branch>` | Same, but for a named project under `$CC_PROJECT_BASE` |
| `cc clean` | List managed worktrees and prune stale ones |
| `cc doctor [--no-probe]` | Diagnose the agent-teams environment |
| `cc install` | Install / update Claude Code to latest |
| `cc help` | Show inline help with current config paths |

`cc` runs Claude in a child process, so `cc go` and `cc wt` never change the directory of the shell you typed them in — when Claude exits, you are back where you started.

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

Installs to `~/.config/zsh/claude-cc/` and adds a `source` line to `~/.zshrc` and/or `~/.bashrc` — whichever matches your login shell or already exists.

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
echo 'source ~/.config/zsh/claude-cc/cc.zsh' >> ~/.zshrc     # zsh
echo 'source ~/.config/zsh/claude-cc/cc.bash' >> ~/.bashrc   # bash
```

Then open a new shell. Other shells (fish, scripts) can run `~/.config/zsh/claude-cc/bin/claude-cc` directly — it takes the same arguments as `cc`.

---

## Configuration

Set these in your rc file (`~/.zshrc` or `~/.bashrc`):

```zsh
export CC_PROJECT_BASE="$HOME/projects"    # where your repos live (default: ~/projects)
export CC_WT_BASE="$HOME/worktrees"        # where worktrees are created (default: ~/worktrees)
```

They are read on every `cc` call, so changing them takes effect immediately. `cc help` always shows the currently active values.

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
  ↓  starts claude in the worktree
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

Every `cc` call runs the current `bin/claude-cc`, so an update takes effect in open shells right away.

**Upgrading from a zsh-only version:** shells that were already open still hold the old `cc`
function. Run `cc reload` once in each of them, or open a new shell.

---

## Requirements

- **zsh** (5.x) or **bash** (3.2+, so macOS `/bin/bash` works)
- **git** (for worktree commands)
- **python3** — only for the settings check in `cc doctor`
- **Claude Code CLI** — install with `cc install` or follow [official docs](https://claude.ai/code)
- **cmux CLI** — only for `--teams` / `cct`; `cc doctor` also uses it for its live probe. Everything else works without it.

---

## Development

```bash
tests/run.sh            # every shell whose shim exists and binary is installed
tests/run.sh bash       # one shell
TEST_BASH=/bin/bash tests/run.sh   # pin the bash that bin/claude-cc runs under
```

The suite uses stub `claude` / `cmux` binaries and a throwaway `HOME`, so it never starts a real session. CI runs it on Linux and macOS (including `/bin/bash` 3.2).

---

## License

MIT — see [LICENSE](./LICENSE)

---

<details>
<summary>한국어 설명</summary>

## cc — Claude Code zsh 래퍼

Claude Code CLI를 감싸는 경량 래퍼입니다. zsh와 bash에서 동작하며, **git worktree 기반 브랜치 격리**, 프로젝트 이동, 세션 정리 기능을 추가합니다.

### 설치

```bash
curl -fsSL https://raw.githubusercontent.com/Ahngbeom/claude-cc/main/install.sh | bash
```

로그인 셸에 맞는 rc 파일, 또는 이미 있는 rc 파일(`~/.zshrc`, `~/.bashrc`)에 source 줄을 추가합니다. 수동으로 설치한다면 zsh는 `cc.zsh`를, bash는 `cc.bash`를 source합니다. 그 밖의 셸에서는 `bin/claude-cc`를 직접 실행합니다.

### 설정

rc 파일(`~/.zshrc` 또는 `~/.bashrc`)에서 환경변수를 설정합니다. `cc`를 호출할 때마다 새로 읽으므로 바꾸면 바로 반영됩니다:

```zsh
export CC_PROJECT_BASE="$HOME/Flyingdoctor"   # 프로젝트 루트
export CC_WT_BASE="$HOME/Flyingdoctor/worktrees"  # worktree 저장 위치
```

### 주요 커맨드

| 커맨드 | 설명 |
|--------|------|
| `cc` | 현재 디렉토리에서 Claude 세션 시작 |
| `cc go <경로>` | 해당 경로에서 Claude 시작 |
| `cc wt <브랜치>` | Worktree 생성(또는 재사용) 후 Claude 시작 |
| `cc wt <프로젝트> <브랜치>` | 지정 프로젝트에서 Worktree 생성 |
| `cc clean` | Worktree 목록 확인 및 prune |
| `cc doctor [--no-probe]` | agent teams 환경 진단 (종료코드 = 실패 개수) |
| `cc help` | 도움말 및 현재 설정 경로 출력 |

Claude는 자식 프로세스에서 실행됩니다. 그래서 `cc go`나 `cc wt`를 실행해도 그 명령을 입력한 셸의 디렉터리는 바뀌지 않고, Claude를 종료하면 원래 위치로 돌아옵니다.

`cc help`를 실행하면 현재 `CC_PROJECT_BASE`, `CC_WT_BASE` 값을 확인할 수 있습니다.

### 전용 플래그

`cc`가 먼저 해석한 뒤 나머지를 `claude`에 넘깁니다. 모든 서브커맨드와 조합됩니다 (예: `cc go ~/projects/my-app --teams`).

| 플래그 | 동작 |
|--------|------|
| `--teams` | `claude` 대신 `cmux claude-teams`로 실행합니다. agent teams가 켜지고 **이름이 붙은** 팀원이 각자 분할 페인에서 열립니다. `--permission-mode`를 직접 주지 않으면 `--permission-mode default`도 함께 붙습니다 — plan 모드에서는 팀원이 생성되지 않으므로, `permissions.defaultMode: plan`을 그대로 물려받으면 teams 세션이 정작 아무것도 못 합니다. 해제하려면 `cct --permission-mode plan`. 축약 별칭: `cct` |
| `--discord` | `--channels plugin:discord@claude-plugins-official` 로 확장됩니다 |

`--teams`와 `cc doctor`의 live probe는 **cmux CLI**가 필요합니다. 나머지 기능은 없어도 동작합니다.

### 새 버전 반영

`cc`는 호출할 때마다 현재의 `bin/claude-cc`를 실행하므로, 업데이트하면 열려 있는 셸에도 바로 반영됩니다.

**zsh 전용 버전에서 업그레이드할 때:** 이미 열려 있던 셸에는 옛 `cc` 함수가 남아 있습니다. 각 셸에서 `cc reload`를 한 번 실행하거나 새 셸을 여세요.

### 요구 사항

- zsh 5.x 또는 bash 3.2 이상(macOS `/bin/bash` 포함)
- git
- python3(`cc doctor`의 설정 점검에만 필요)

</details>
