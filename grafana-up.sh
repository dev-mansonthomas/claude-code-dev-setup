#!/usr/bin/env bash
# grafana-up.sh — start the local Claude Code monitoring dashboards (Grafana).
# Wraps the claude-code-otel stack (installed by ./setup.sh). Telemetry is already
# enabled in settings.json, so once this is up, new Claude Code sessions stream
# metrics to http://localhost:3000.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

OTEL_DIR="${OTEL_DIR:-$HOME/Tools/claude-code-otel}"
GRAFANA_URL="http://localhost:3000"

step "Claude Code monitoring — starting Grafana"

if [[ ! -d "$OTEL_DIR" ]]; then
  err "Monitoring stack not found at $OTEL_DIR"
  log "Install it first:  ./setup.sh    (or: bash scripts/60-dev-tools.sh)"
  exit 1
fi
has docker || die "Docker not found. Install Docker Desktop: brew install --cask docker"
docker info >/dev/null 2>&1 || die "Docker isn't running — start Docker Desktop, then re-run ./grafana-up.sh"

info "Bringing up OTEL Collector + Prometheus + Loki + Grafana (detached)..."
if [[ -f "$OTEL_DIR/Makefile" ]] && grep -qE '^up:' "$OTEL_DIR/Makefile"; then
  make -C "$OTEL_DIR" up
else
  ( cd "$OTEL_DIR" && docker compose up -d )
fi

# Best-effort: wait until Grafana answers, so the browser opens to a ready page.
if has curl; then
  info "Waiting for Grafana to be ready..."
  tries=0
  while (( tries < 25 )); do
    if curl -fsS -o /dev/null "$GRAFANA_URL/api/health" 2>/dev/null; then break; fi
    sleep 1; tries=$((tries + 1))
  done
fi

ok "Monitoring is up."
log ""
log "  Grafana : $GRAFANA_URL   (login: admin / admin)"
log "  Shows   : token usage, cost, sessions, tool latency, errors"
log "  Telemetry is already enabled in ~/.claude/settings.json — metrics appear as"
log "  you use Claude Code (start a fresh session if you don't see data yet)."
log ""
log "  Stop it with: ./grafana-down.sh"

if has open; then open "$GRAFANA_URL" >/dev/null 2>&1 || true; fi
