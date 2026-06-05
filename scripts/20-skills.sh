#!/usr/bin/env bash
# 20-skills.sh — install Agent Skills globally for Claude Code via `npx skills`.
# Idempotent: re-running updates existing skills. Targets the global Claude Code
# skills dir (~/.claude/skills) with `-g -a claude-code`.
#
# Skill sources (verified):
#   fcenedes/redis_sa_skills  -> Redis SA toolkit (caveman, rtk-cli, redis-*-ui,
#                                playwright-*, redis-insight-plugin, agent-* …)
#   redis/agent-skills        -> Official Redis engineering skills (redis-core,
#                                redis-vector-search, redis-security, …)
#   anthropics/skills         -> frontend-design (production-grade UI)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Agent Skills"

if ! has npx; then
  warn "npx not found (Node). Skipping skills. Install Node via nvm, then re-run."
  exit 0
fi

# Edit this list to add/remove skill collections. Format: "<owner/repo> <flags>"
SKILL_SOURCES=(
  "fcenedes/redis_sa_skills --all"
  "redis/agent-skills --all"
  "anthropics/skills --skill frontend-design"
)

info "Currently installed skills:"
npx -y skills list -a claude-code 2>/dev/null || warn "Could not list skills (first run downloads the CLI)."

for src in "${SKILL_SOURCES[@]}"; do
  # shellcheck disable=SC2086  # intentional word-splitting of repo + flags
  set -- $src
  repo="$1"; shift
  info "Adding $repo $* ..."
  # -g: global  -a claude-code: target Claude Code (non-interactive, CI-friendly)
  # shellcheck disable=SC2086
  npx -y skills add "$repo" "$@" -g -a claude-code || warn "Failed to add $repo (continuing)."
done

ok "Skills step complete. Run 'npx skills list' anytime; 'npx skills update' to refresh."
