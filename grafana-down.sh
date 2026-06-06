#!/usr/bin/env bash
# grafana-down.sh — stop the local Claude Code monitoring dashboards.
# Stops the claude-code-otel containers. Your telemetry settings stay in place;
# nothing is collecting until you run ./grafana-up.sh again.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

OTEL_DIR="${OTEL_DIR:-$HOME/Tools/claude-code-otel}"

step "Claude Code monitoring — stopping Grafana"

if [[ ! -d "$OTEL_DIR" ]]; then
  warn "Nothing to stop — stack not found at $OTEL_DIR"
  exit 0
fi
if ! has docker; then
  warn "Docker not found — nothing to stop."
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  ok "Docker isn't running — monitoring is already stopped."
  exit 0
fi

if [[ -f "$OTEL_DIR/Makefile" ]] && grep -qE '^down:' "$OTEL_DIR/Makefile"; then
  make -C "$OTEL_DIR" down
else
  ( cd "$OTEL_DIR" && docker compose down )
fi

ok "Monitoring stopped (containers down). Telemetry settings stay in place."
log "Start again with: ./grafana-up.sh"
