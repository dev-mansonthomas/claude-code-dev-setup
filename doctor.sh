#!/usr/bin/env bash
# doctor.sh — read-only health check. Prints what's installed/configured.
# Changes nothing. Run it any time to see the state of your Claude Code setup.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

pass=0; fail=0; warns=0
check() { # check "label" <cmd...>  -> ✓/✗ by exit status
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; pass=$((pass+1)); else err "$label"; fail=$((fail+1)); fi
}
note() { warn "$*"; warns=$((warns+1)); }
desc() { if [[ -L "$1" ]]; then echo "(symlink)"; else echo "(file)"; fi; }

step "Toolchain"
check "Homebrew"                   has brew
check "git"                        has git
check "Node (npx)"                 has npx
check "Python 3"                   has python3
check "GitHub CLI (gh)"            has gh
check "gitleaks (secret scanning)" has gitleaks
check "uv / uvx (Redis MCP)"       has uv
check "jq"                         has jq
if has gh; then
  if gh auth status >/dev/null 2>&1; then ok "gh authenticated"; else note "gh not authenticated (gh auth login)"; fi
fi

step "Claude Code"
if CLAUDE="$(claude_bin)"; then
  ok "claude CLI: $CLAUDE ($("$CLAUDE" --version 2>/dev/null || echo '?'))"; pass=$((pass+1))
else
  err "claude CLI not found on PATH"; fail=$((fail+1)); CLAUDE=""
fi

step "Global config (~/.claude)"
CDIR="$HOME/.claude"
if [[ -e "$CDIR/CLAUDE.md" ]]; then
  ok "CLAUDE.md $(desc "$CDIR/CLAUDE.md")"; pass=$((pass+1))
else
  err "CLAUDE.md missing"; fail=$((fail+1))
fi
if [[ -e "$CDIR/settings.json" ]]; then
  if has jq && jq -e . "$CDIR/settings.json" >/dev/null 2>&1; then
    ok "settings.json valid JSON $(desc "$CDIR/settings.json")"; pass=$((pass+1))
  else
    note "settings.json present but not validated (jq missing or invalid)"
  fi
else
  err "settings.json missing"; fail=$((fail+1))
fi
if [[ -x "$CDIR/hooks/git-secret-guard.sh" || -L "$CDIR/hooks/git-secret-guard.sh" ]]; then
  ok "secret-guard hook installed"; pass=$((pass+1))
else
  note "secret-guard hook not installed"
fi
cmds=$(find "$CDIR/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$cmds" -gt 0 ]]; then ok "custom slash commands: $cmds"; else note "no custom slash commands in ~/.claude/commands"; fi

step "Skills"
skills=$(find "$CDIR/skills" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
if [[ "$skills" -gt 0 ]]; then ok "installed skills: $skills"; else note "no skills found (run scripts/20-skills.sh)"; fi

step "MCP servers"
if [[ -n "$CLAUDE" ]]; then
  if "$CLAUDE" mcp list >/dev/null 2>&1; then
    "$CLAUDE" mcp list 2>/dev/null | sed 's/^/    /' || true
  else
    note "Could not list MCP servers (none configured, or run inside a project)."
  fi
else
  note "Skipping MCP check (no claude CLI)."
fi

step "Dev tooling (monitoring & multi-project)"
check "claude-monitor (usage gauge)" has claude-monitor
if has claude-squad || has cs; then ok "Claude Squad (cs)"; pass=$((pass+1)); else note "Claude Squad not installed (scripts/60-dev-tools.sh)"; fi
if has npx; then ok "ccusage / ccstatusline available via npx"; pass=$((pass+1)); else note "npx missing — ccusage/ccstatusline unavailable"; fi
oteldir="${OTEL_DIR:-$HOME/Tools/claude-code-otel}"
if [[ -d "$oteldir/.git" ]]; then ok "claude-code-otel cloned"; pass=$((pass+1)); else note "claude-code-otel not cloned (optional Grafana stack)"; fi
if [[ -e "$CDIR/settings.json" ]] && has jq; then
  if jq -e '.statusLine' "$CDIR/settings.json" >/dev/null 2>&1; then ok "status line wired (ccstatusline)"; pass=$((pass+1)); else note "no statusLine in settings.json"; fi
  if jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY' "$CDIR/settings.json" >/dev/null 2>&1; then ok "OpenTelemetry wired"; pass=$((pass+1)); else note "OTEL not wired in settings.json"; fi
fi

step "Summary"
printf '  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n' \
  "$C_GREEN" "$pass" "$C_RESET" "$C_YELLOW" "$warns" "$C_RESET" "$C_RED" "$fail" "$C_RESET"
if [[ "$fail" -eq 0 ]]; then ok "Looks good."; else warn "Run ./setup.sh to fix the failures above."; fi
exit 0
