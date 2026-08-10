#!/usr/bin/env bash
# 30-mcp.sh — register the MCP servers worth having at user scope:
#   context7            up-to-date, version-specific library docs (kills hallucinated APIs)
#   playwright          drive a real browser for web testing/automation
#   sequential-thinking structured multi-step reasoning
#   redis-docs          official Redis documentation (HTTP MCP at https://redis.io/mcp)
#   obscura             stealth headless browser (VM-only; anti-detect FALLBACK for web research)
# The Redis *data* MCP is per-project (needs a DB + connection string) so we only PRINT a
# ready-to-paste snippet rather than add it globally.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "MCP servers (user scope)"

if ! CLAUDE="$(claude_bin)"; then
  warn "claude not found on PATH. Open a new terminal after step 10, then re-run: ./01-setup.sh"
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
# --browser chromium: use Playwright's bundled Chromium (installed by vm-provision). WITHOUT this the
# MCP defaults to the "chrome" channel (branded Google Chrome), which has NO arm64 Linux build → the
# MCP fails to launch a browser in the VM. (Re-run needs a fresh register; add_mcp skips if it exists.)
add_mcp playwright npx -y @playwright/mcp@latest --browser chromium

# --- Sequential thinking ---------------------------------------------------
add_mcp sequential-thinking npx -y @modelcontextprotocol/server-sequential-thinking

# --- Redis docs (official HTTP MCP: current Redis docs; user scope, no secret) --------------
# HTTP transport, so it doesn't fit add_mcp (which is stdio "-- <cmd>"); register it directly.
if mcp_exists redis-docs; then
  ok "MCP 'redis-docs' already configured"
else
  info "Adding MCP 'redis-docs' (HTTP)..."
  if "$CLAUDE" mcp add --scope user --transport http redis-docs https://redis.io/mcp; then
    ok "Added 'redis-docs'"
  else
    warn "Could not add 'redis-docs' (continuing)."
  fi
fi

# --- obscura (stealth headless browser MCP — VM-only; register only if the binary is present) --
# vm-provision.sh installs the obscura binary; on the host it's absent, so skip cleanly.
if has obscura; then
  add_mcp obscura obscura mcp
else
  ok "obscura MCP skipped (binary not installed — it's a VM-only tool)"
fi

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
