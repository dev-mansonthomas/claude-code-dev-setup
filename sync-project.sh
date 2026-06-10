#!/usr/bin/env bash
# sync-project.sh — pull updated *kit-managed* files from project-template/ into an
# existing project. SAFE by design:
#   • only touches a small set of kit-owned infra files (secret-scan hook, editorconfig,
#     secret-scan CI) — files meant to stay identical across all projects;
#   • NEVER touches your customized files (CLAUDE.md, README.md, docs/, .gitignore,
#     .gitleaks.toml, .env.example) or language-specific CI (ci-node.yml / ci-python.yml);
#   • dry-run by default (shows diffs); pass --apply to copy; it NEVER commits.
#
# Usage: ./sync-project.sh <project-dir> [--apply]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

TEMPLATE="$HERE/project-template"

DEST=""; APPLY=0
for a in "$@"; do
  case "$a" in
    --apply)   APPLY=1 ;;
    -h|--help) log "Usage: ./sync-project.sh <project-dir> [--apply]"; exit 0 ;;
    -*)        die "Unknown option: $a" ;;
    *)         DEST="$a" ;;
  esac
done
[[ -n "$DEST" ]] || { err "Usage: ./sync-project.sh <project-dir> [--apply]"; exit 1; }
[[ -d "$DEST" ]] || die "Not a directory: $DEST"
[[ -d "$TEMPLATE" ]] || die "Template not found at $TEMPLATE"

# Kit-owned infra files that should stay identical across projects (safe to sync).
MANAGED_FILES="
.githooks/pre-commit
.editorconfig
.github/workflows/secret-scan.yml
"

step "Sync kit files -> $DEST  ($([[ $APPLY == 1 ]] && echo APPLY || echo dry-run))"

changed=0
# shellcheck disable=SC2086  # intentional word-splitting of the file list
for rel in $MANAGED_FILES; do
  [[ -z "$rel" ]] && continue
  src="$TEMPLATE/$rel"; dst="$DEST/$rel"
  [[ -f "$src" ]] || continue
  if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
    ok "up to date: $rel"
    continue
  fi
  changed=$((changed + 1))
  if [[ -f "$dst" ]]; then
    warn "differs: $rel"
    diff -u "$dst" "$src" 2>/dev/null | sed 's/^/    /' | head -40 || true
  else
    warn "missing in project: $rel"
  fi
  if [[ $APPLY == 1 ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    case "$rel" in .githooks/*|*.sh) chmod +x "$dst" ;; esac
    ok "updated $rel"
  fi
done

echo
if [[ $changed -eq 0 ]]; then
  ok "Nothing to sync — project is current."
elif [[ $APPLY == 1 ]]; then
  ok "$changed file(s) updated. Review then commit in the project:"
  log "    git -C \"$DEST\" add -A && git -C \"$DEST\" diff --cached && git -C \"$DEST\" commit"
  log "    (first time only, per clone: git -C \"$DEST\" config core.hooksPath .githooks)"
else
  info "$changed file(s) differ. Re-run with --apply to copy them in, then review + commit."
fi
info "Not synced (project-customized — edit by hand if needed): CLAUDE.md, README.md, docs/,"
info "  .gitignore, .gitleaks.toml, .env.example, and language CI (ci-node.yml / ci-python.yml)."
exit 0
