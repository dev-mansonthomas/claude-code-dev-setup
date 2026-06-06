#!/usr/bin/env bash
# 60-dev-tools.sh — install the monitoring & multi-project tooling (standard step).
# Install-only and idempotent. Skipped when setup.sh is run with --no-extras.
#   • claude-monitor (live usage/limit gauge) -> uv tool (pipx fallback)
#   • Claude Squad (cs)                        -> Homebrew + short 'cs' symlink
#   • claude-code-otel (Grafana stack)         -> git clone only (start later: make up)
#   • ccusage & ccstatusline                   -> run via npx (no install needed)
# The status line (ccstatusline) and OpenTelemetry are wired via settings.json (step 50).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Dev tooling — monitoring & multi-project"

OTEL_DIR="${OTEL_DIR:-$HOME/Tools/claude-code-otel}"

# ccusage + ccstatusline: no install, run on demand via npx
if has npx; then
  ok "ccusage & ccstatusline available via npx (no install needed)"
else
  warn "npx not found — install Node (nvm install --lts) for ccusage/ccstatusline."
fi

# claude-monitor — live usage/limit gauge
if has uv; then
  info "Installing/updating claude-monitor (uv tool)..."
  if uv tool install claude-monitor || uv tool upgrade claude-monitor; then
    ok "claude-monitor ready (claude-monitor --plan max20 --view realtime)"
  else
    warn "claude-monitor install failed (fallback: pipx install claude-monitor)."
  fi
elif has pipx; then
  pipx install claude-monitor || warn "pipx install of claude-monitor failed."
else
  warn "uv/pipx missing — preflight installs uv; or run: pip install claude-monitor"
fi

# Claude Squad (cs) — many sessions in one TUI
if has brew; then
  if brew list --formula claude-squad >/dev/null 2>&1; then
    ok "claude-squad already installed"
  else
    info "Installing claude-squad..."
    brew install claude-squad || warn "brew install claude-squad failed."
  fi
  if has claude-squad && ! has cs; then
    if ln -s "$(brew --prefix)/bin/claude-squad" "$(brew --prefix)/bin/cs" 2>/dev/null; then
      ok "linked short alias 'cs' -> claude-squad"
    else
      warn "could not create 'cs' alias (a 'cs' may already exist)."
    fi
  fi
else
  warn "Homebrew not found — cannot install Claude Squad."
fi

# claude-code-otel — clone only; you start the dashboards later with 'make up'
if [[ -d "$OTEL_DIR/.git" ]]; then
  ok "claude-code-otel already cloned at $OTEL_DIR"
elif has git; then
  info "Cloning claude-code-otel into $OTEL_DIR ..."
  mkdir -p "$(dirname "$OTEL_DIR")"
  git clone --depth 1 https://github.com/ColeMurray/claude-code-otel.git "$OTEL_DIR" \
    || warn "git clone of claude-code-otel failed."
else
  warn "git not found — cannot clone claude-code-otel."
fi

ok "Dev tooling step complete."
info "Grafana dashboards (when you want them): cd \"$OTEL_DIR\" && make up  ->  http://localhost:3000 (admin/admin)"
info "Customize the status line anytime: npx -y ccstatusline@latest"
