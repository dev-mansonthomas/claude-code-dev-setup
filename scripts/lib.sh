#!/usr/bin/env bash
# lib.sh — shared helpers for the claude-code-dev-setup scripts.
# Sourced by setup.sh, doctor.sh and every scripts/NN-*.sh.
# Not meant to be executed directly.

# ---------------------------------------------------------------------------
# Homebrew: quiet + deterministic for scripted installs (export 0 to opt out).
#   NO_ENV_HINTS   — hide the "did you know / future default" hint blocks
#   NO_AUTO_UPDATE — don't re-index all formulae on every single install call
# ---------------------------------------------------------------------------
export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"

# ---------------------------------------------------------------------------
# Colours (disabled when not a TTY or when NO_COLOR is set)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log()   { printf '%s\n' "$*"; }
info()  { printf '%s•%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

step()  { printf '\n%s%s==>%s %s%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_BOLD" "$*$C_RESET"; }

# ---------------------------------------------------------------------------
# Predicates
# ---------------------------------------------------------------------------
# has CMD -> true if CMD is on PATH
has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Confirmation prompt. Returns 0 (yes) / 1 (no).
# Honours AUTO_YES=1 (set by `setup.sh --yes`) to answer yes non-interactively.
# Defaults to "yes" when stdin is not a TTY (CI) unless overridden.
# ---------------------------------------------------------------------------
confirm() {
  local prompt="${1:-Continue?}" reply
  if [[ "${AUTO_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 0
  fi
  printf '%s [Y/n] ' "$prompt"
  read -r reply
  [[ -z "$reply" || "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---------------------------------------------------------------------------
# Back up a path that is a *real* file/dir (not a symlink we manage) so we
# never silently clobber the user's existing config. No-op if absent or if
# it is already a symlink.  Backups go under ~/.claude/backups/setup-<ts>/.
# ---------------------------------------------------------------------------
: "${BACKUP_DIR:=$HOME/.claude/backups/setup-$(date +%Y%m%d-%H%M%S)}"

backup_path() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0   # nothing there
  if [[ -L "$target" ]]; then
    return 0                                        # our symlink — safe to replace
  fi
  mkdir -p "$BACKUP_DIR"
  local base; base="$(basename "$target")"
  cp -R "$target" "$BACKUP_DIR/$base"
  warn "Backed up existing $target -> $BACKUP_DIR/$base"
}

# ---------------------------------------------------------------------------
# OS guard — this kit targets Apple Silicon macOS.
# ---------------------------------------------------------------------------
require_macos_arm() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This kit targets macOS. Detected: $(uname -s)"
  if [[ "$(uname -m)" != "arm64" ]]; then
    warn "Detected $(uname -m) (expected arm64 / Apple Silicon). Continuing anyway."
  fi
}

# ---------------------------------------------------------------------------
# Ensure a Homebrew package (formula or --cask) is installed.
#   ensure_brew <formula>
#   ensure_brew_cask <cask>
# ---------------------------------------------------------------------------
ensure_brew() {
  local pkg="$1"
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    info "Installing $pkg via brew..."
    brew install "$pkg"
  fi
}

ensure_brew_cask() {
  local pkg="$1"
  if brew list --cask "$pkg" >/dev/null 2>&1; then
    ok "$pkg (cask) already installed"
  else
    info "Installing $pkg (cask) via brew..."
    brew install --cask "$pkg"
  fi
}

# ---------------------------------------------------------------------------
# Resolve the claude binary even when PATH isn't fully loaded (non-login shell).
# Echoes the path, or nothing if not found.
# ---------------------------------------------------------------------------
claude_bin() {
  if has claude; then command -v claude; return 0; fi
  local c
  for c in "$HOME/.local/bin/claude" "/opt/homebrew/bin/claude" "$HOME/.claude/local/claude"; do
    [[ -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Repo root (directory that contains this lib.sh's parent). Callers can rely on it.
# shellcheck disable=SC2034
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
