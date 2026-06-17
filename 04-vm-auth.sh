#!/usr/bin/env bash
# 04-vm-auth.sh — authenticate the VM's Claude with a long-lived OAuth token (host-side).
#
# Runs `claude setup-token` on the HOST (it opens a browser and prints a token), then stores
# the token in a host-only file (chmod 600). `ccvm` injects it into each VM session — the token
# is never written into the VM image or under ~/Projects, so it can't be committed.
#   Rotate: re-run this script.    Revoke: https://console.anthropic.com
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

TOKEN_FILE="${CC_TOKEN_FILE:-$HOME/.config/claude-code-dev-setup/oauth-token}"

step "Authenticate the VM (host-side OAuth token)"
has claude || die "Claude Code CLI not found on the host. Run ./01-setup.sh first (or open a new shell)."

info "'claude setup-token' will open a browser. Approve it, then COPY the sk-ant-oat01-… token it prints."
log ""
claude setup-token || die "claude setup-token failed (needs a Claude Pro/Max/Team/Enterprise subscription)."
log ""

# Read the token back without echoing it or leaving it in shell history.
printf 'Paste the token here (hidden): '
read -rs tok || true
printf '\n'
tok="$(printf '%s' "${tok:-}" | tr -d '[:space:]')"
[[ -n "$tok" ]] || die "No token entered — nothing saved."
case "$tok" in
  sk-ant-oat01-*) ;;
  *) warn "That doesn't look like a setup-token (expected sk-ant-oat01-…) — saving it anyway." ;;
esac

mkdir -p "$(dirname "$TOKEN_FILE")"
( umask 077; printf '%s\n' "$tok" > "$TOKEN_FILE" )
chmod 600 "$TOKEN_FILE" 2>/dev/null || true
ok "Saved -> $TOKEN_FILE (chmod 600, host-only)."
log ""
log "  ccvm injects this token into each VM session (never stored in the VM)."
log "  Test it:  ccvm <project>     Rotate: re-run ./04-vm-auth.sh     Revoke: https://console.anthropic.com"
