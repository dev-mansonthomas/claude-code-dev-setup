#!/usr/bin/env bash
# grafana-down.sh — stop the Claude Code monitoring dashboards (Grafana) running in the Colima VM.
# Stops the claude-code-otel containers in the VM. Telemetry settings stay in place; nothing is
# collected until you run ./grafana-up.sh again.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

step "Claude Code monitoring — stopping Grafana (in the Colima VM)"

has colima || die "Colima not installed."
if ! colima status >/dev/null 2>&1; then
  ok "Colima VM not running — monitoring is already stopped."
  exit 0
fi

# shellcheck disable=SC2016  # $HOME/$d are intentionally expanded by the VM's bash, not the host
if colima ssh -- bash -lc 'd="$HOME/claude-code-otel"; [ -d "$d" ] || exit 0; cd "$d" && make down'; then
  ok "Monitoring stopped (containers down). Telemetry settings stay in place."
  log "Start again with: ./grafana-up.sh"
else
  warn "Could not stop the stack (maybe already down, or the VM isn't provisioned)."
fi
