#!/usr/bin/env bash
# 10-claude-code.sh — install (or confirm) the Claude Code CLI.
# Uses the official native installer (no Node dependency, self-updating).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Claude Code CLI"

if claude_bin >/dev/null; then
  bin="$(claude_bin)"
  ok "Claude Code already installed: $bin ($("$bin" --version 2>/dev/null || echo '?'))"
  info "It self-updates in the background; nothing to do."
  exit 0
fi

info "Installing Claude Code via the official native installer..."
log "  curl -fsSL https://claude.ai/install.sh | bash"
if confirm "Proceed with the native install?"; then
  curl -fsSL https://claude.ai/install.sh | bash
else
  warn "Skipped Claude Code install."
  exit 0
fi

# The installer drops the binary in ~/.local/bin (added to PATH in your shell rc).
if bin="$(claude_bin)"; then
  ok "Installed: $bin ($("$bin" --version 2>/dev/null || echo '?'))"
  warn "Open a new terminal (or 'exec zsh -l') so 'claude' is on your PATH."
else
  warn "Install ran but 'claude' isn't on PATH yet — open a new terminal and run 'claude --version'."
fi
