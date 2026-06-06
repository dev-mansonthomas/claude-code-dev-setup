#!/usr/bin/env bash
# new-project.sh — scaffold a new project from project-template/.
#
# Usage: ./new-project.sh <name> [dest] [--redis | --no-mcp]
#   <name>      project name (letters, digits, . _ -); fills {{PROJECT_NAME}}
#   [dest]      target directory (default: ../<name>)
#   --redis     add the Redis MCP to this project (.mcp.json) without asking
#   --no-mcp    don't add any project MCP (and don't prompt)
#   (interactive runs without a flag are asked about the Redis MCP; default No)
#   REDIS_URL=…  override the Redis connection string (default redis://127.0.0.1:6379/0)
#
# Copies the template, fills placeholders ({{PROJECT_NAME}}, {{DATE}}), optionally
# wires a per-project MCP, then runs `git init`. Refuses to overwrite an existing path.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

# --- parse args: flags + positional <name> [dest] --------------------------
REDIS_MCP=""           # "" = ask (if interactive), "yes" / "no" = decided
positional=()
for arg in "$@"; do
  case "$arg" in
    --redis)             REDIS_MCP=yes ;;
    --no-mcp|--no-redis) REDIS_MCP=no ;;
    -h|--help)           log "Usage: ./new-project.sh <name> [dest] [--redis|--no-mcp]"; exit 0 ;;
    -*)                  die "Unknown option: $arg" ;;
    *)                   positional+=("$arg") ;;
  esac
done
NAME="${positional[0]:-}"
DEST="${positional[1]:-}"

if [[ -z "$NAME" ]]; then
  err "Usage: ./new-project.sh <name> [dest] [--redis|--no-mcp]"
  exit 1
fi
if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  die "Invalid project name '$NAME' — use letters, digits, dot, underscore, dash (no spaces or slashes)."
fi

TEMPLATE="$HERE/project-template"
[[ -d "$TEMPLATE" ]] || die "Template not found at $TEMPLATE"

dest="${DEST:-../$NAME}"
[[ ! -e "$dest" ]] || die "Target already exists: $dest"

step "Scaffolding '$NAME'"
mkdir -p "$dest"
cp -R "$TEMPLATE"/. "$dest"/

info "Filling placeholders ({{PROJECT_NAME}} -> $NAME, {{DATE}} -> $(date +%F))..."
find "$dest" -type f \( -name '*.md' -o -name '*.json' -o -name '*.toml' -o -name '*.yml' \) \
  -exec sed -i.bak -e "s/{{PROJECT_NAME}}/$NAME/g" -e "s/{{DATE}}/$(date +%F)/g" {} +
find "$dest" -name '*.bak' -delete

# --- optional per-project MCP servers --------------------------------------
# Project-specific MCPs (not useful for every project) are offered here, not in
# the global setup. Redis first; add more options below as needed.
add_redis="$REDIS_MCP"
if [[ -z "$add_redis" ]]; then
  if [[ -t 0 ]]; then
    printf 'Add the Redis MCP to this project (lets the agent query your Redis)? [y/N] '
    read -r reply || reply=""
    if [[ "$reply" =~ ^[Yy] ]]; then add_redis=yes; else add_redis=no; fi
  else
    add_redis=no   # non-interactive default: don't add
  fi
fi
if [[ "$add_redis" == yes ]]; then
  url="${REDIS_URL:-redis://127.0.0.1:6379/0}"
  cat > "$dest/.mcp.json" <<JSON
{
  "mcpServers": {
    "redis": {
      "command": "uvx",
      "args": ["--from", "redis-mcp-server@latest", "redis-mcp-server", "--url", "$url"]
    }
  }
}
JSON
  ok "Added Redis MCP -> .mcp.json ($url)"
  info "Edit .mcp.json to point at your DB. For auth, set REDIS_URL and avoid committing secrets."
fi

( cd "$dest" && git init -q && git add -A )

ok "Created $dest"
log ""
log "  Next: cd $dest && claude     (then run /brainstorm to qualify the idea)"
[[ "$add_redis" == yes ]] && log "  Redis MCP is wired (.mcp.json) — Claude will start it in this project."
exit 0
