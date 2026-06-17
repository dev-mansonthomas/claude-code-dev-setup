#!/usr/bin/env bash
# 05-new-project.sh — scaffold a new project from project-template/.
#
# Usage: ./05-new-project.sh <name> [dest] [--redis | --no-mcp] [--no-launch]
#   <name>      project name (letters, digits, . _ -); fills {{PROJECT_NAME}}
#   [dest]      target directory (default: ../<name>)
#   --redis     add the Redis MCP to this project (.mcp.json) without asking
#   --no-mcp    don't add any project MCP (and don't prompt)
#   --no-launch don't hand off to `ccvm` (VS Code + VM) at the end — just scaffold
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
LAUNCH=1               # after scaffolding, hand off to `ccvm` (VS Code on host + Claude in the VM)
positional=()
for arg in "$@"; do
  case "$arg" in
    --redis)             REDIS_MCP=yes ;;
    --no-mcp|--no-redis) REDIS_MCP=no ;;
    --no-launch)         LAUNCH=0 ;;
    -h|--help)           log "Usage: ./05-new-project.sh <name> [dest] [--redis|--no-mcp] [--no-launch]"; exit 0 ;;
    -*)                  die "Unknown option: $arg" ;;
    *)                   positional+=("$arg") ;;
  esac
done
NAME="${positional[0]:-}"
DEST="${positional[1]:-}"

if [[ -z "$NAME" ]]; then
  err "Usage: ./05-new-project.sh <name> [dest] [--redis|--no-mcp]"
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

(
  cd "$dest"
  git init -q
  if [[ -f .githooks/pre-commit ]]; then
    chmod +x .githooks/pre-commit
    git config core.hooksPath .githooks   # enable the local secret-scan pre-commit hook
  fi
  git add -A
)

ok "Created $dest"
[[ "$add_redis" == yes ]] && info "Redis MCP wired (.mcp.json) — Claude starts it in this project."

# Hand off to the isolated VM workflow: open VS Code on the host + a Claude session in the VM.
abs="$(cd "$dest" && pwd)"
if [[ "$LAUNCH" == 1 && -t 1 && -x "$HERE/ccvm" ]]; then
  case "$abs" in
    "$HOME/Projects"|"$HOME/Projects"/*)
      log ""; log "  → launching ccvm (VS Code on the host + Claude inside the VM)…"
      exec "$HERE/ccvm" "$abs" ;;
    *)
      warn "Project is outside ~/Projects → not mounted in the VM; skipping ccvm."
      log "  Move it under ~/Projects, then: ccvm $NAME" ;;
  esac
else
  log ""
  log "  Next: ccvm $NAME     (opens VS Code on the host + Claude inside the VM)"
  log "        no VM yet? run ./03-vm-up.sh once. Prefer local? cd $dest && claude"
fi
exit 0
