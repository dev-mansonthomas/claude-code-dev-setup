#!/usr/bin/env bash
# 30-mcp.sh — register the MCP servers worth having at user scope:
#   context7            up-to-date, version-specific library docs (kills hallucinated APIs)
#   playwright          drive a real browser for web testing/automation
#   sequential-thinking structured multi-step reasoning
# Redis MCP is per-project (needs a DB + connection string) so we only PRINT a
# ready-to-paste snippet rather than add it globally.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "MCP servers (user scope)"

if ! CLAUDE="$(claude_bin)"; then
  warn "claude not found on PATH. Open a new terminal after step 10, then re-run: ./setup.sh"
  exit 0
fi

mcp_exists() { "$CLAUDE" mcp list 2>/dev/null | grep -qi "^${1}\b\|[[:space:]]${1}[[:space:]]\|${1}:"; }

add_mcp() {
  local name="$1"; shift
  if mcp_exists "$name"; then
    ok "MCP '$name' already configured"
    return 0
  fi
  info "Adding MCP '$name'..."
  if "$CLAUDE" mcp add --scope user "$name" -- "$@"; then
    ok "Added '$name'"
  else
    warn "Could not add '$name' (continuing)."
  fi
}

# --- Context7 (optional API key for higher rate limits) --------------------
C7_KEY="${CONTEXT7_API_KEY:-}"
if [[ -z "$C7_KEY" && "${AUTO_YES:-0}" != "1" && -t 0 ]]; then
  printf 'Context7 API key (optional, Enter to skip — get one free at context7.com/dashboard): '
  read -r C7_KEY
fi
if [[ -n "$C7_KEY" ]]; then
  add_mcp context7 npx -y @upstash/context7-mcp --api-key "$C7_KEY"
else
  add_mcp context7 npx -y @upstash/context7-mcp
fi

# --- Playwright ------------------------------------------------------------
add_mcp playwright npx -y @playwright/mcp@latest

# --- Sequential thinking ---------------------------------------------------
add_mcp sequential-thinking npx -y @modelcontextprotocol/server-sequential-thinking

# --- Redis MCP: per-project snippet (not added globally) -------------------
cat <<'SNIPPET'

  ── Redis MCP (add per project, when the agent should query your DB) ──
  Point it at the project's Redis (like you did in Augment Intent):

    claude mcp add --scope project redis -- \
      uvx --from redis-mcp-server@latest redis-mcp-server \
      --url redis://<user>:<password>@127.0.0.1:6399/0

  This writes .mcp.json in the project (commit it — it has no secret if you
  use an env var for the password). See docs/claude-code-setup.md §Toolbox.

SNIPPET

ok "MCP step complete. Verify with: claude mcp list"
