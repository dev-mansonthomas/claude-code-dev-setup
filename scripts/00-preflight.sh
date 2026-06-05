#!/usr/bin/env bash
# 00-preflight.sh — make sure the base toolchain this kit relies on exists.
# Installs the small, safe extras (gh, gitleaks, uv, jq) via Homebrew.
# Does NOT touch node/python (you manage those with nvm/pyenv).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Preflight — checking base toolchain"
require_macos_arm

# --- Homebrew is the foundation for everything below -----------------------
if ! has brew; then
  err "Homebrew is required but not found."
  log "Install it first (see your Mac OS Setup doc), then re-run:"
  # shellcheck disable=SC2016  # intentional literal install command for the user to copy
  log '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi
ok "Homebrew present ($(brew --version | head -1))"

# --- Tools you should already have (managed elsewhere) ---------------------
# git ships with the Xcode CLT; warn rather than force a brew install.
has git    || warn "git not found — run: xcode-select --install"
has node   || warn "node not found — install via nvm (see Mac OS Setup doc)"
has npx    || warn "npx not found — comes with Node; check your nvm install"
has python3 || warn "python3 not found — install via pyenv (see Mac OS Setup doc)"

# --- Small, safe extras this kit needs -------------------------------------
# gh       : create/push the GitHub repo, auth helper
# gitleaks : powers the git-secret-guard hook
# uv       : runs the Redis MCP server via uvx (per project)
# jq       : JSON inspection used by doctor.sh / config merge
ensure_brew gh
ensure_brew gitleaks
ensure_brew uv
ensure_brew jq

# --- gh auth status (don't fail the run, just report) ----------------------
if has gh; then
  if gh auth status >/dev/null 2>&1; then
    ok "GitHub CLI authenticated"
  else
    warn "GitHub CLI not authenticated — run: gh auth login  (Protocol: SSH)"
  fi
fi

ok "Preflight complete"
