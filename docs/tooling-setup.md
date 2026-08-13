# Monitoring & multi-project tooling (host — OFF by default; lives in the VM)

This host tooling is **OFF by default**: the monitoring/multi-project stack runs in the **VM**
(installed by `./03-vm-up.sh`). To add it to the **host** too, run `./01-setup.sh --with-extras`.
This page is reference (copy it into your Mac OS setup guide).

## What the dev-tools step installs

The **dev-tools** step (`scripts/60-dev-tools.sh`) — run in the VM by `03-vm-up.sh`, or on the host
only with `./01-setup.sh --with-extras` — installs:

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

> These are host extras, **off by default** — `./01-setup.sh --with-extras` opts the host in; the
> VM gets them via `./03-vm-up.sh`. (The `statusLine`/`env` blocks in `claude-config/settings.json`
> are wired regardless; drop them if you don't want the status line / telemetry.)

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
