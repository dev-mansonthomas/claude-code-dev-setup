# Claude Code — one-page cheat sheet

> Print this. Full guide: [claude-code-setup.md](claude-code-setup.md).

## The loop
```
/brainstorm → /spec → /plan-feature → build → /code-review + /security-review → /ship → /doc-sync
qualify       spec     TDD plan        impl     review                            gate    docs
```

## Launch
```bash
claude            # start in current repo
claude -c         # continue last session
claude --resume   # pick a past session
claude -p "…"     # headless (scripts/CI)
./05-new-project.sh app        # scaffold ../app  (or: make new-project NAME=app)
```

## VM (Colima) — the isolated workspace (default)
| Goal | Command |
|---|---|
| **Shell into the VM** | `colima ssh` |
| VM shell at `~/Projects` (OAuth token injected) | `ccvm` |
| Edit on host + Claude **inside** the VM, at a project | `ccvm <project>` |
| Start / status / stop the VM | `./03-vm-up.sh` · `colima status` · `colima stop` |
| One-off command in the VM | `colima ssh -- bash -lc '<cmd>'` |

> Files under `~/Projects` are shared host↔VM (virtiofs). Edit on the host; build/test/Claude run in the VM. Push & deploy from the **host** (the VM holds no credentials).

## In-session essentials
| Key/Cmd | Action |
|---|---|
| `Shift+Tab` | cycle modes → **plan mode** (read-only planning) |
| `/context` | what's filling the window |
| `/compact` | summarize to free context (same task) |
| `/clear` | reset for a new task |
| `@file` | pin a file into context |
| `#text` | save a durable fact to CLAUDE.md |
| "think hard" / "ultrathink" | more reasoning budget |
| `/model` · `/fast` | choose model · toggle Fast mode |
| `/mcp` · `/agents` · `/plugin` | servers · subagents · plugins |

## Memory = files, not chat
- `CLAUDE.md` (global `~/.claude` + per-project) and `docs/` are the brain.
- Anything that must outlive the session → write it to a file.

## Use the right tool
| Need | Reach for |
|---|---|
| Current lib version/API | Context7 MCP — "use context7" |
| Build/validate web UI | `frontend-design`, Playwright MCP, `playwright-test` |
| Redis modeling/ops | `redis-core`, `redis-query-engine`, `redis-vector-search`, `redis-observability`, `redis-security` |
| Query project's Redis | per-project Redis MCP (`.mcp.json`) |
| Terse output / compact CLI | `caveman`, `rtk-cli` |

## Security & git (non-negotiable)
- Secrets → env vars + `.gitignore`; the secret-guard hook blocks leaky commits.
- Conventional Commits; branch off `main`; **push only when asked**.
- `/security-review` for auth/input/data; `/ship` before any push.

## Skills upkeep
```bash
ls ~/.claude/skills          # installed skills
./01-setup.sh                   # idempotent: refresh skills + config
./02-doctor.sh                  # full health check
```

## Monitoring & parallel
| Goal | Command |
|---|---|
| Usage now / today | `npx ccusage@latest` · `npx ccusage@latest blocks --live` |
| Live limit gauge | `claude-monitor --plan max20 --view realtime` |
| Dashboards (Grafana) | `./grafana-up.sh` · `./grafana-down.sh` |
| Context / status line | `/context` · `npx -y ccstatusline@latest` (one-time setup) |
| Parallel project | `claude --worktree <name>` (isolated branch + worktree) |
| Many sessions (TUI) | `cs` (Claude Squad: tmux + worktrees) |

Full guide: [workspace-and-monitoring.md](workspace-and-monitoring.md).

## Fix-its
| Symptom | Fix |
|---|---|
| `claude` not found | new terminal / `exec zsh -l` |
| MCP not responding | `/mcp` re-auth; run its command standalone |
| Hook blocked a commit | real secret? fix it. False positive? allowlist in `.gitleaks.toml` |
| Skill won't trigger | name it explicitly; confirm with `ls ~/.claude/skills` |
