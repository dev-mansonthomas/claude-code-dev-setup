#!/usr/bin/env bash
# 50-global-config.sh — install the global Claude Code config into ~/.claude.
# Default mode = symlink (so `git pull` in this repo updates both your MacBooks).
# Pass COPY_MODE=1 (setup.sh --copy) for plain copies instead.
# Any pre-existing *real* file is backed up first; our own symlinks are replaced.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Global Claude config -> ~/.claude"

CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/commands"

MODE="symlink"; [[ "${COPY_MODE:-0}" == "1" ]] && MODE="copy"
info "Install mode: $MODE"

# install_file <src> <dest>
install_file() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || { warn "missing source $src"; return 0; }
  backup_path "$dest"
  rm -f "$dest"
  if [[ "$MODE" == "copy" ]]; then
    cp "$src" "$dest"
  else
    ln -sfn "$src" "$dest"
  fi
  ok "${MODE/symlink/linked} $(basename "$dest")"
}

# Make the hook executable at the source so the link/copy is runnable.
chmod +x "$REPO_ROOT/claude-config/hooks/git-secret-guard.sh" 2>/dev/null || true

# --- settings.json: never blow away an existing one silently ----------------
if [[ -e "$CLAUDE_DIR/settings.json" && ! -L "$CLAUDE_DIR/settings.json" ]]; then
  warn "Existing ~/.claude/settings.json found."
  if confirm "Replace it with this kit's settings.json (a backup is kept)?"; then
    install_file "$REPO_ROOT/claude-config/settings.json" "$CLAUDE_DIR/settings.json"
  else
    warn "Kept your settings.json. Merge manually from claude-config/settings.json if you like."
  fi
else
  install_file "$REPO_ROOT/claude-config/settings.json" "$CLAUDE_DIR/settings.json"
fi

# --- CLAUDE.md + hook -------------------------------------------------------
install_file "$REPO_ROOT/claude-config/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
install_file "$REPO_ROOT/claude-config/hooks/git-secret-guard.sh" "$CLAUDE_DIR/hooks/git-secret-guard.sh"

# --- custom slash commands --------------------------------------------------
shopt -s nullglob
for cmd in "$REPO_ROOT"/claude-commands/*.md; do
  install_file "$cmd" "$CLAUDE_DIR/commands/$(basename "$cmd")"
done
shopt -u nullglob

ok "Global config installed. Backups (if any) under $BACKUP_DIR"
