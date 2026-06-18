#!/usr/bin/env bash
# grafana-up.sh — start the Claude Code monitoring dashboards (Grafana).
# The OTEL/Grafana stack runs INSIDE the Colima VM (provisioned by 03-vm-up.sh at
# ~/claude-code-otel). Run this from the HOST: it ensures the VM is up, brings the stack up in
# the VM (idempotent — starts the Docker images if not already running), waits for Grafana, and
# opens your browser. Lima forwards the VM's ports, so the dashboard is at http://localhost:3000
# on your Mac. Stop it with ./grafana-down.sh.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

GRAFANA_URL="http://localhost:3000"

step "Claude Code monitoring — starting Grafana (in the Colima VM)"

has colima || die "Colima not installed — run ./03-vm-up.sh first."
if ! colima status >/dev/null 2>&1; then
  info "Colima VM not running — starting it..."
  colima start
fi

info "Bringing up OTEL Collector + Prometheus + Grafana inside the VM (idempotent)..."
# shellcheck disable=SC2016  # $HOME/$d are intentionally expanded by the VM's bash, not the host
if ! colima ssh -- bash -lc 'd="$HOME/claude-code-otel"; [ -d "$d" ] || exit 3; cd "$d" && make up'; then
  die "Could not start the monitoring stack in the VM. If it's missing, (re)provision with: ./03-vm-up.sh"
fi

# Lima forwards the VM's published ports to the host, so Grafana is on localhost.
if has curl; then
  info "Waiting for Grafana to answer on $GRAFANA_URL ..."
  tries=0
  while (( tries < 30 )); do
    if curl -fsS -o /dev/null "$GRAFANA_URL/api/health" 2>/dev/null; then break; fi
    sleep 1; tries=$((tries + 1))
  done
fi

ok "Monitoring is up."
log ""
log "  Grafana : $GRAFANA_URL   (login: admin / admin)"
log "  Shows   : token usage, cost, sessions, tool latency, errors"
log "  Claude in the VM streams telemetry here automatically (settings.json → localhost:4317)."
log "  Stop it with: ./grafana-down.sh"
log ""

if has open; then open "$GRAFANA_URL" >/dev/null 2>&1 || true; fi
