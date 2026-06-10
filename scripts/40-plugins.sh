#!/usr/bin/env bash
# 40-plugins.sh — install Claude Code plugins (marketplace + plugin).
# Tries the non-interactive CLI; if the verbs differ in your Claude version, it prints
# the exact in-session `/plugin` commands. Idempotent + best-effort (never fatal).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Plugins"

if ! CLAUDE="$(claude_bin)"; then
  warn "claude not found on PATH — skipping (open a new terminal, then re-run setup)."
  exit 0
fi

# Format: "<marketplace-repo>|<plugin-name>"
PLUGINS=(
  "obra/superpowers-marketplace|superpowers"   # TDD/planning/debug methodology; makes Claude use its skills
)

for entry in "${PLUGINS[@]}"; do
  mkt="${entry%%|*}"; plug="${entry#*|}"
  info "Plugin '$plug' (marketplace: $mkt)"
  "$CLAUDE" plugin marketplace add "$mkt" >/dev/null 2>&1 || true
  if "$CLAUDE" plugin install "$plug" >/dev/null 2>&1; then
    ok "installed $plug"
  else
    warn "Couldn't install '$plug' via the CLI (verb differs) — do it in a Claude session:"
    log "    /plugin marketplace add $mkt"
    log "    /plugin                      # then browse & install '$plug'"
  fi
done

info "Tip: run /using-superpowers in a session so Claude actively reaches for its skills."
ok "Plugins step complete."
