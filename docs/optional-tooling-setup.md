# Optional tooling — install & wiring

Self-contained companion to [workspace-and-monitoring.md](workspace-and-monitoring.md).
Two things you can copy straight into your **Mac OS setup guide**:

- **(a)** a one-command, install-only script for the monitoring / multi-project tools;
- **(b)** the exact `settings.json` blocks to wire **ccstatusline** (status line) and
  **OpenTelemetry** (Grafana dashboards).

> Everything here is **additive and reversible**. The script never deletes or edits your
> configs; the `settings.json` changes are two JSON keys you add (and can remove).

---

## (a) One-command installer

Save it as `scripts/60-dev-tools.sh` in the kit (or anywhere), make it executable, and run
it. It's **idempotent** (safe to re-run) and **install-only** — verified `shellcheck`-clean
with no destructive operations.

What it does:
- **ccusage** & **ccstatusline** — nothing to install (they run via `npx`); it just checks Node.
- **claude-monitor** (live limit gauge) — `uv tool install` (or `pipx` fallback).
- **Claude Squad** (`cs`) — Homebrew + a short `cs` symlink, created only if `cs` is free.
- **claude-code-otel** — `git clone` only (you start it later with `make up`).

```bash
#!/usr/bin/env bash
# 60-dev-tools.sh — install the OPTIONAL monitoring & multi-project tools.
# Install-only and idempotent: it never deletes files or edits your configs.
#   • ccusage & ccstatusline    -> no install (run via npx); we just check Node.
#   • claude-monitor (gauge)    -> uv tool install
#   • Claude Squad (cs)         -> Homebrew + a short 'cs' symlink (only if free)
#   • claude-code-otel          -> git clone only (you start it later with 'make up')
# Override the clone location with: OTEL_DIR=/path ./60-dev-tools.sh
set -euo pipefail

if [[ -t 1 ]]; then B=$'\033[1;36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'; else B=; G=; Y=; R=; fi
info(){ printf '%s•%s %s\n' "$B" "$R" "$*"; }
ok(){   printf '%s✓%s %s\n' "$G" "$R" "$*"; }
warn(){ printf '%s!%s %s\n' "$Y" "$R" "$*" >&2; }
has(){ command -v "$1" >/dev/null 2>&1; }

OTEL_DIR="${OTEL_DIR:-$HOME/Tools/claude-code-otel}"

# 1) ccusage + ccstatusline — no install, run on demand via npx (just need Node)
if has npx; then
  ok "Node/npx present — ccusage & ccstatusline run via npx (no install needed)."
else
  warn "npx not found — install Node (nvm install --lts) to use ccusage/ccstatusline."
fi

# 2) Claude Code Usage Monitor (live limit gauge)
if has uv; then
  info "Installing/updating claude-monitor (uv tool)..."
  if uv tool install claude-monitor || uv tool upgrade claude-monitor; then
    ok "claude-monitor ready (run: claude-monitor --plan max20 --view realtime)"
  else
    warn "claude-monitor install failed (fallback: pipx install claude-monitor)."
  fi
elif has pipx; then
  info "Installing claude-monitor (pipx)..."
  pipx install claude-monitor || warn "pipx install failed."
else
  warn "uv/pipx not found — 'brew install uv' then re-run, or 'pip install claude-monitor'."
fi

# 3) Claude Squad (cs) via Homebrew
if has brew; then
  if brew list --formula claude-squad >/dev/null 2>&1; then
    ok "claude-squad already installed."
  else
    info "Installing claude-squad..."
    brew install claude-squad || warn "brew install claude-squad failed."
  fi
  if has claude-squad && ! has cs; then
    if ln -s "$(brew --prefix)/bin/claude-squad" "$(brew --prefix)/bin/cs" 2>/dev/null; then
      ok "linked short alias 'cs' -> claude-squad"
    else
      warn "could not create 'cs' alias (optional; a 'cs' may already exist)."
    fi
  fi
else
  warn "Homebrew not found — see https://github.com/smtg-ai/claude-squad to install."
fi

# 4) claude-code-otel — clone only (you launch it later with 'make up')
if [[ -d "$OTEL_DIR/.git" ]]; then
  ok "claude-code-otel already present at $OTEL_DIR"
elif has git; then
  info "Cloning claude-code-otel into $OTEL_DIR ..."
  mkdir -p "$(dirname "$OTEL_DIR")"
  git clone --depth 1 https://github.com/ColeMurray/claude-code-otel.git "$OTEL_DIR" \
    || warn "git clone failed."
else
  warn "git not found — cannot clone claude-code-otel."
fi

cat <<EOF

${G}Done — install-only, nothing was deleted or reconfigured.${R}
Finish the interactive/optional bits yourself:
  • Status line:  npx -y ccstatusline@latest          (TUI; writes settings.json)
  • Live gauge:   claude-monitor --plan max20 --view realtime
  • Usage report: npx ccusage@latest blocks --live
  • OTEL stack:   cd "$OTEL_DIR" && make up            (Grafana: http://localhost:3000, admin/admin)
                  then enable telemetry (settings.json snippet in this guide)
  • Parallel:     claude --worktree <name>     or     cs   (Claude Squad)
EOF
```

Run it:
```bash
chmod +x scripts/60-dev-tools.sh
./scripts/60-dev-tools.sh          # re-runnable; OTEL_DIR=/path to change clone location
```

---

## (b) Wire ccstatusline + OpenTelemetry in `settings.json`

> **Where:** with this kit, `~/.claude/settings.json` is a **symlink** to
> `claude-config/settings.json` in the repo. So editing it is **version-controlled** — make
> the change, review the diff, **commit it**, and your second MacBook gets it on `git pull`.

Add these two top-level keys **alongside** the keys the kit already ships (`model`,
`permissions`, `hooks`, …):

**Status line (ccstatusline):**
```json
"statusLine": {
  "type": "command",
  "command": "npx -y ccstatusline@latest",
  "padding": 0,
  "refreshInterval": 10
}
```
*(Tip: running `npx -y ccstatusline@latest` once opens a TUI that writes this block for you —
so (b) for the status line can be done either by hand or by the TUI.)*

**OpenTelemetry (feeds the claude-code-otel Grafana stack):**
```json
"env": {
  "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
  "OTEL_METRICS_EXPORTER": "otlp",
  "OTEL_LOGS_EXPORTER": "otlp",
  "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
  "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
}
```

Put together with the kit's existing settings, the file looks like this:
```json
{
  "model": "opus",
  "includeCoAuthoredBy": true,

  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0,
    "refreshInterval": 10
  },

  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
  },

  "permissions": { "allow": ["…keep your existing list…"], "deny": [], "ask": [] },
  "hooks": { "PreToolUse": ["…keep your existing secret-guard…"] }
}
```

Notes:
- **Privacy:** the OTEL endpoint is **`localhost`** — telemetry goes only to *your* local
  collector (`make up`), nothing leaves the machine. If the collector isn't running, the
  exporter just can't connect — harmless.
- **Prefer it off by default?** Drop the `env` block and instead enable telemetry only when
  you want it, per session: `CLAUDE_CODE_ENABLE_TELEMETRY=1 claude` (with the other `OTEL_*`
  vars exported in that shell).
- After editing, validate it's still valid JSON: `jq -e . ~/.claude/settings.json` and run
  `./doctor.sh`.

---

## (c) Add this to your Mac OS setup guide

Copy this page into the **"Claude Code setup"** tab of your Mac OS setup Google Doc (you're
handling the copy yourself — no automated Drive push).
