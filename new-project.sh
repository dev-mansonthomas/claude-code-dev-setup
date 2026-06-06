#!/usr/bin/env bash
# new-project.sh — scaffold a new project from project-template/.
#
# Usage: ./new-project.sh <name> [dest]
#   <name>  project name (letters, digits, . _ -); fills {{PROJECT_NAME}}
#   [dest]  target directory (default: ../<name>)
#
# Copies the template, fills placeholders ({{PROJECT_NAME}}, {{DATE}}), then runs
# `git init`. Refuses to overwrite an existing path. (`make new-project` calls this.)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

NAME="${1:-}"
DEST="${2:-}"

if [[ -z "$NAME" ]]; then
  err "Usage: ./new-project.sh <name> [dest]"
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

( cd "$dest" && git init -q && git add -A )

ok "Created $dest"
log ""
log "  Next: cd $dest && claude     (then run /brainstorm to qualify the idea)"
