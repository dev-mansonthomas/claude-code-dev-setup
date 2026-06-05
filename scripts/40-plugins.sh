#!/usr/bin/env bash
# 40-plugins.sh — plugins are optional and best managed interactively, so this
# step is informational: it reports the current plugin state and tells you the
# exact in-session commands to add a marketplace and install plugins.
# (The non-interactive plugin CLI verbs change between versions; we don't guess.)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Plugins (optional, interactive)"

if ! CLAUDE="$(claude_bin)"; then
  warn "claude not found on PATH — skipping plugin info."
  exit 0
fi

# Show current marketplaces/plugins if the CLI exposes them (don't fail if not).
if "$CLAUDE" plugin marketplace list >/dev/null 2>&1; then
  info "Configured marketplaces:"
  "$CLAUDE" plugin marketplace list 2>/dev/null || true
fi

cat <<'INFO'

  Plugins bundle commands + agents + skills + hooks under one install.
  Add them from inside a Claude Code session (most reliable):

    /plugin marketplace add anthropics/claude-code     # add a marketplace
    /plugin                                            # browse & install (TUI)

  You already have the Redis + SA skills installed directly (step 20), so
  plugins are optional. Revisit this once you find a marketplace you trust.

INFO

ok "Plugins step complete (nothing changed automatically)."
