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
| `cc install` | Install / update Claude Code to latest |
| `cc help` | Show inline help with current config paths |

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

---

## Requirements

- **zsh** (tested on zsh 5.9+)
- **git** (for worktree commands)
- **Claude Code CLI** — install with `cc install` or follow [official docs](https://claude.ai/code)

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
| `cc help` | 도움말 및 현재 설정 경로 출력 |

`cc help`를 실행하면 현재 `CC_PROJECT_BASE`, `CC_WT_BASE` 값을 확인할 수 있습니다.

</details>
