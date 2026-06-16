#!/usr/bin/env bash
# cc — work inside the always-on Colima VM (the default isolated environment).
#   cc <project>   open VS Code on the host project + a Claude session INSIDE the VM
#   cc             shell into the VM (at ~/Projects)
# You edit on the host (files are mounted into the VM); Claude + Docker + tests run in the VM.
set -euo pipefail
PROJECTS="$HOME/Projects"
has(){ command -v "$1" >/dev/null 2>&1; }

has colima || { echo "Colima not installed — run ./vm-up.sh first." >&2; exit 1; }
colima status >/dev/null 2>&1 || { echo "Colima VM not running — start it with ./vm-up.sh (or: colima start)." >&2; exit 1; }

# Auth: inject a long-lived OAuth token into the VM session if you've set one up.
# Generate it on the HOST (which has a browser) with `claude setup-token`, then save it to
# the file below. It's read from the host only and passed per-session — never written into
# the VM image or under ~/Projects, so it can't be committed. Absent → log in inside the VM.
TOKEN_FILE="${CC_TOKEN_FILE:-$HOME/.config/claude-code-dev-setup/oauth-token}"
tok="${CLAUDE_CODE_OAUTH_TOKEN:-}"
if [[ -z "$tok" && -r "$TOKEN_FILE" ]]; then tok="$(tr -d '[:space:]' < "$TOKEN_FILE")"; fi

# No arg → just drop into the VM.
if [[ $# -eq 0 ]]; then
  ssh_cmd=(colima ssh --)
  if [[ -n "$tok" ]]; then ssh_cmd+=(env "CLAUDE_CODE_OAUTH_TOKEN=$tok"); fi
  ssh_cmd+=(bash -lc "cd '$PROJECTS' 2>/dev/null || true; exec bash -l")
  exec "${ssh_cmd[@]}"
fi

# Resolve <project> to an absolute host path under ~/Projects (mounted at the same path in the VM).
name="$1"
if [[ -d "$name" ]]; then abs="$(cd "$name" && pwd)"; else abs="$PROJECTS/$name"; fi
[[ -d "$abs" ]] || { echo "Project not found: $abs" >&2; exit 1; }
case "$abs" in
  "$PROJECTS"|"$PROJECTS"/*) ;;
  *) echo "⚠ $abs is outside $PROJECTS — it isn't mounted in the VM. Put projects under $PROJECTS." >&2; exit 1 ;;
esac

# Open the editor on the host (edits the mounted files).
if has code; then
  code "$abs" >/dev/null 2>&1 || true
else
  echo "(VS Code 'code' not on PATH — skipping editor; install: brew install --cask visual-studio-code)" >&2
fi

# Enter the VM at the project and launch Claude there.
echo "→ entering VM at $abs  (Claude Code runs inside the VM; edit on the host)"
ssh_cmd=(colima ssh --)
if [[ -n "$tok" ]]; then ssh_cmd+=(env "CLAUDE_CODE_OAUTH_TOKEN=$tok"); fi
ssh_cmd+=(bash -lc "cd '$abs' && exec claude")
exec "${ssh_cmd[@]}"
