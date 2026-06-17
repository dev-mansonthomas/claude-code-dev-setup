# Monitoring & multi-project tooling (installed by `01-setup.sh`)

This is **part of the standard install** — `./01-setup.sh` installs and wires everything
below automatically. This page is reference (copy it into your Mac OS setup guide).

## What the standard install does

The **dev-tools** step (`scripts/60-dev-tools.sh`, run by `01-setup.sh`) installs:

| Tool | What it's for | How it's installed |
|------|---------------|--------------------|
| **claude-monitor** | live usage/limit gauge (burn-rate, limit prediction) | `uv tool install claude-monitor` |
| **Claude Squad** (`cs`) | manage many parallel sessions (tmux + worktrees) | Homebrew + `cs` symlink |
| **claude-code-otel** | Grafana dashboards stack (OTEL collector + Prometheus + Loki + Grafana) | `git clone` → `~/Tools/claude-code-otel` |
| **ccusage** / **ccstatusline** | usage reports / status line | run via `npx` (no install) |

And `settings.json` (installed by step 50) wires automatically:
- **Status line → ccstatusline** — context %, tokens, cost, model, git branch/worktree.
- **OpenTelemetry** — exports metrics/logs to a **local** collector for the claude-code-otel
  Grafana dashboards.

> Don't want the tooling? `./01-setup.sh --no-extras` skips this step (and you can drop the
> `statusLine`/`env` blocks from `claude-config/settings.json`).

## The one manual step: start the dashboards

The OTEL stack is **cloned but not started** (it runs Docker containers — starting them is
your call, not something an installer should do silently). When you want Grafana:

```bash
./grafana-up.sh      # start the dashboards (opens http://localhost:3000, admin/admin)
./grafana-down.sh    # stop them
```

Telemetry is **local-only** (`localhost:4317`) — nothing leaves your machine. If the stack
isn't running, the exporter simply can't connect (harmless). To turn telemetry off entirely,
remove the `env` block from `settings.json`.

## Customize the status line (optional)

ccstatusline ships with sensible defaults, so it works immediately. To pick widgets/themes:

```bash
npx -y ccstatusline@latest        # interactive TUI; updates your settings.json block
```
Since `~/.claude/settings.json` is symlinked to this repo, review the diff and **commit it**
so your other MacBook gets the same status line.

## Daily commands

```bash
npx ccusage@latest blocks --live              # live usage within the current 5-hour block
claude-monitor --plan max20 --view realtime   # gauge with limit prediction (pin on a side screen)
# in-session:
/context                                      # context-window usage breakdown
claude --worktree <name>                      # isolated parallel session (own branch + worktree)
cs                                            # Claude Squad: create/switch many sessions
```

## Verify

```bash
./02-doctor.sh        # the "Dev tooling" section shows: claude-monitor, cs, otel clone, status line, OTEL
```

See **[workspace-and-monitoring.md](workspace-and-monitoring.md)** for how to use each tool in
depth and the multi-monitor desk layout.
