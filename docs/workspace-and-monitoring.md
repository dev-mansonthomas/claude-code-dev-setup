# Monitoring & multi-project workspace

How to **watch token/limit usage**, **monitor context**, **observe the agent**, and
**run 2–3 projects in parallel** — plus how to lay it all out on a multi-monitor desk.

> **Framing for subscription plans (Max/Pro):** you don't pay per token, so the goal
> isn't saving dollars — it's **not slamming into your usage window** (5-hour / weekly
> limits) in the middle of a sprint. The tools below are your *fuel gauge* and *flight
> recorder*, not a billing report.

> **Already installed:** `./setup.sh` installs and wires all of this automatically
> (see [tooling-setup.md](tooling-setup.md)). The sections below focus on *using* each
> piece day-to-day; the install commands are kept inline for reference.

---

## 1. Token, cost & limit tracking

### Built-in `/cost`
In any session, `/cost` shows the current session's token/cost summary. Zero install.
On subscription plans it's informational (usage, not a bill). See the official
[cost guide](https://code.claude.com/docs/en/costs).

### ccusage — local reports + live block monitor
Reads Claude Code's local JSONL logs and turns them into reports. Nothing leaves your
machine; no install needed (runs via `npx`).

```bash
npx ccusage@latest                 # today's summary
npx ccusage@latest daily           # per-day table
npx ccusage@latest monthly         # per-month
npx ccusage@latest session         # per-session
npx ccusage@latest blocks          # 5-hour billing/usage blocks
npx ccusage@latest blocks --live   # ← LIVE dashboard: burn rate within the current block
```
Useful flags: `--since/--until DATE`, `--breakdown` (per-model), `--instances` / `--project`
(group by project), `--json`. (`bunx ccusage` works too if you use Bun.)

**Use it for:** "how much have I burned today / this block, and am I trending toward the limit?"

### Claude Code Usage Monitor — real-time gauge with limit prediction
A terminal dashboard with burn-rate analysis and **ML predictions of when you'll hit the
limit**. Best kept open on a secondary screen.

```bash
uv tool install claude-monitor      # recommended (or: pipx install claude-monitor / pip install claude-monitor)
claude-monitor                      # launch (aliases: ccmonitor, ccm, cmonitor)
```
Key flags:
```bash
claude-monitor --plan max20         # pro | max5 | max20 | custom (default: custom w/ P90 auto-detect)
claude-monitor --view realtime      # realtime | daily | monthly
claude-monitor --timezone Europe/Paris --refresh-rate 5 --theme dark
```
**Use it for:** the always-visible "time/tokens left before the wall" gauge.

> **ccusage vs Usage Monitor:** `ccusage` = quick on-demand reports + a live block view;
> `claude-monitor` = a persistent gauge that *predicts* limit exhaustion. They complement
> each other — many people glance at `ccusage blocks --live` ad hoc and keep
> `claude-monitor` pinned on a side screen.

---

## 2. Context monitoring & status line

### Built-in `/context` and `/statusline`
- **`/context`** — visualizes what's filling the context window right now (system prompt,
  files, tools, history). Run it when a session feels heavy to decide `/compact` vs `/clear`.
- **`/statusline`** — describe in plain English what you want, and Claude generates a
  status-line script for you. Zero install.

### ccstatusline — a permanent, rich status line
A configurable status line ([sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline))
that shows a **context bar (%)**, token usage, session cost, model, git branch/worktree,
block-reset timer, and more — refreshed live at the bottom of every session.

```bash
npx -y ccstatusline@latest          # opens a TUI; pick widgets/theme, it writes settings.json for you
```
It writes this into your Claude Code `settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0,
    "refreshInterval": 10
  }
}
```
Context color thresholds are tunable: `--context-low-threshold` (green below, default 50)
and `--context-medium-threshold` (yellow below, default 80).

> **Heads-up for this kit:** `~/.claude/settings.json` is a **symlink** to
> `claude-config/settings.json` in this repo (see [README](../README.md)). So when the
> ccstatusline TUI edits `settings.json`, it edits the repo copy — which is exactly what
> you want: **review the diff and commit it**, and both MacBooks get the same status line
> on the next `git pull`.

---

## 3. Agent observability — OpenTelemetry → Grafana

Claude Code has **native OpenTelemetry**: it emits metrics (tokens, cost, sessions),
events (prompts, tool results), and traces (prompt → model → tool → hook). Point it at a
local collector and you get real dashboards.

**`claude-code-otel`** ([ColeMurray/claude-code-otel](https://github.com/ColeMurray/claude-code-otel))
bundles a turnkey stack (OTEL Collector + Prometheus + Loki + Grafana with ready dashboards).

```bash
git clone https://github.com/ColeMurray/claude-code-otel.git
cd claude-code-otel
make up                              # starts collector + Prometheus + Loki + Grafana
```
Then enable telemetry in Claude Code (export before launching `claude`, or add an `env`
block to `~/.claude/settings.json`):
```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```
Open Grafana at **http://localhost:3000** (default `admin` / `admin`); Prometheus is on
`:9090`. Dashboards cover cost/usage, sessions & activity, tool performance, latency, and
error logs (metrics like `claude_code.token.usage`, `claude_code.cost.usage`,
`claude_code.session.count`).

> **Privacy:** the endpoint is **`localhost`** — telemetry goes only to *your* collector,
> nothing leaves the machine. Overkill for a quick fix; genuinely useful when you run
> several agents for hours and want to see where time/tokens went.

To make it always-on without touching your shell, add to `~/.claude/settings.json`
(remember: that edits the repo copy — commit it):
```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
  }
}
```
(If the collector isn't running, the exporter simply can't connect — harmless.)

---

## 4. Multiple projects / parallel sessions

### Git worktrees (native) — the foundation
A worktree is a separate working directory + branch sharing one repo. Each Claude session
in its own worktree means **edits never collide**. Claude Code has this built in
([docs](https://code.claude.com/docs/en/worktrees)):

```bash
# First time in a repo, run plain `claude` once to accept the trust dialog.
claude --worktree feature-auth      # isolated worktree under .claude/worktrees/feature-auth (branch worktree-feature-auth)
claude --worktree bugfix-123        # run in a second terminal → a second isolated session
claude --worktree "#1234"           # base the worktree on PR #1234
claude -w                           # omit the name → Claude generates one (e.g. bright-running-fox)
```
- Worktrees branch from `origin/HEAD` (clean) by default; set `"worktree": {"baseRef": "head"}`
  in settings to branch from your local `HEAD` instead.
- **Copy gitignored files** (like `.env`) into each worktree with a `.worktreeinclude`
  file (uses `.gitignore` syntax). The scaffolded project template already ignores
  `.claude/worktrees/`.
- **Cleanup:** exit with no changes → worktree+branch auto-removed; with changes → Claude
  asks. Manual: `git worktree list` / `git worktree remove <path>`.
- **Subagents** can isolate too: add `isolation: worktree` to a subagent's frontmatter, or
  say "use worktrees for your agents".

Manual equivalent (full control over location/branch):
```bash
git worktree add ../myapp-feature-a -b feature-a
cd ../myapp-feature-a && claude
git worktree remove ../myapp-feature-a
```

### Claude Squad — manage many sessions from one TUI
When juggling several agents/projects at once, [Claude Squad](https://github.com/smtg-ai/claude-squad)
gives a terminal UI over **tmux + git worktrees** — each session isolated, reviewable
before you apply/push.

```bash
brew install claude-squad
ln -s "$(brew --prefix)/bin/claude-squad" "$(brew --prefix)/bin/cs"   # short alias
cs                                   # launch
```
Keys inside `cs`: `n` new session · `N` new with a starting prompt · `↑/↓` (`j/k`) move ·
`↵`/`o` attach to the selected session · `ctrl-q` detach · `D` kill it.

> **Discipline:** cap yourself at **2–4 parallel sessions**. Past that, the bottleneck is
> *your* review capacity, not Claude — and quality drops. Keep the usage gauge (§1)
> visible so three agents don't burn your whole window at once.

---

## 5. Multi-monitor workspace organization

Tuned for the setup: **two 38" 4K** (one **portrait**, one **landscape**) + the **MacBook
13"/16"** screen below. Give each surface a *job* matched to its shape.

```
 ┌──────────────────┐   ┌──────────────────────────────────────┐
 │  38" PORTRAIT     │   │            38" LANDSCAPE               │
 │  "read & review"  │   │            "drive"                     │
 │                   │   │  ┌──────────────────┐ ┌─────────────┐  │
 │ • agent plan      │   │  │  Claude Code      │ │   Editor     │  │
 │   (plan mode)     │   │  │  (active session) │ │   IDE        │  │
 │ • specs / docs/   │   │  │                   │ │  (VS Code /  │  │
 │ • full-file diffs │   │  │                   │ │   IntelliJ)  │  │
 │ • /context output │   │  └──────────────────┘ └─────────────┘  │
 │ • logs / browser  │   │                                        │
 └──────────────────┘   └──────────────────────────────────────┘
            ┌──────────────────────────────────────┐
            │      MacBook 13"/16"  "glance"        │
            │  claude-monitor (live gauge) | Grafana │
            │  ccusage blocks --live | Slack/Teams   │
            └──────────────────────────────────────┘
```

**Why this mapping**
- **Landscape 38" = where you drive.** Split it: Claude Code (iTerm2) on one side, your
  editor on the other. Eyes live here. On a 38", thirds work well (Claude | editor | a
  narrow browser/preview).
- **Portrait 38" = where you read.** Tall = perfect for long content without scrolling:
  the agent's **plan**, `docs/specs/*`, **full diffs** during `/code-review`, `/context`
  output, and logs. Reading code top-to-bottom and reviewing diffs is far nicer vertically.
- **MacBook screen = glance band.** Low-attention, always-on dashboards: `claude-monitor`
  (or `ccusage blocks --live`), the Grafana tab, and comms. You glance; you don't stare.

**Running 2–3 projects at once — two patterns**
- **Spaces per project (simple):** put each project in its own macOS **Space**, each Space
  using the same layout above. Swipe (Ctrl+←/→) to switch projects. Keep
  *System Settings → Desktop & Dock → "Automatically rearrange Spaces"* **off** (your Mac
  setup doc already disables this) so projects stay put, and turn **"Displays have separate
  Spaces" on** so each monitor keeps its own Space.
- **Claude Squad cockpit (dense):** run `cs` full-height on the **landscape** screen to see
  all sessions in one list; use the **portrait** screen for the diff/review of the
  currently-selected session; keep the gauge on the MacBook screen. Each session is its own
  worktree, so the three projects never collide.

**macOS mechanics**
- **Magnet** (you already have it) — snap windows to halves/thirds fast. On the 38"
  landscape, thirds; on portrait, top/bottom halves.
- **iTerm2** — build the split-pane layout once, then *Window → Save Window Arrangement*
  and set it to restore on launch. Use a **profile per project** (each with its working
  directory) so a new window opens straight into the right repo.
- **Per-monitor roles stay stable** because Spaces rearrangement is off — muscle memory
  builds fast.
- *(Optional, power users)* a tiling WM like **AeroSpace** or **Rectangle Pro** can script
  these layouts; only worth it if manual snapping annoys you.

**Glanceable, not noisy**
Keep exactly one usage gauge visible while you work. The point of the monitoring screen is
to answer "am I about to hit the limit / is an agent stuck?" at a glance — then back to the
landscape screen to drive.

---

### See also
- [tooling-setup.md](tooling-setup.md) — what `setup.sh` installs & wires (ccstatusline, OTEL) + finishing steps.
- [claude-code-setup.md](claude-code-setup.md) — the full onboarding guide & toolbox.
- [cheatsheet.md](cheatsheet.md) — one-page daily reference.
