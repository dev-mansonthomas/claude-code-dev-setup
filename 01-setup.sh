#!/usr/bin/env bash
# 01-setup.sh — one command to bring a Mac to "professional Claude Code" parity.
# Idempotent: safe to re-run. Each step lives in scripts/NN-*.sh.
#
# Usage:
#   ./01-setup.sh                # host baseline, NON-interactive (CLI + skills + MCP + global config)
#   ./01-setup.sh --copy         # copy global config instead of symlinking
#   ./01-setup.sh --no-mcp       # skip MCP server registration
#   ./01-setup.sh --no-plugins   # skip the plugins info step
#   ./01-setup.sh --with-extras  # ALSO install HOST monitoring/multi-project tooling (default: off)
#   ./01-setup.sh --interactive  # confirm before each step (default: non-interactive)
#   CONTEXT7_API_KEY=xxx ./01-setup.sh   # use a Context7 key (optional; else keyless)
#   ./01-setup.sh --help
#
# The isolated VM (./03-vm-up.sh) is the recommended runtime; this prepares the host baseline.
# Monitoring & multi-project tooling run INSIDE the VM, so host extras are OFF by default
# (--with-extras adds them to the host too).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

WITH_MCP=1
WITH_PLUGINS=1
WITH_EXTRAS=0   # host monitoring/multi-project tooling: OFF by default (it runs inside the VM)
export COPY_MODE="${COPY_MODE:-0}"
export AUTO_YES="${AUTO_YES:-1}"   # non-interactive by default; --interactive to prompt

usage() { sed -n '2,/^set -/{/^set -/!p;}' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)       export COPY_MODE=1 ;;
    --no-mcp)     WITH_MCP=0 ;;
    --no-plugins) WITH_PLUGINS=0 ;;
    --with-extras) WITH_EXTRAS=1 ;;
    --no-extras)   WITH_EXTRAS=0 ;;   # default; accepted for explicitness/back-compat
    --yes|-y)         export AUTO_YES=1 ;;
    --interactive|-i) export AUTO_YES=0 ;;
    -h|--help)    usage ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

printf '%s\n' "$C_BOLD${C_CYAN}
  Claude Code — professional dev setup
  =====================================$C_RESET"
info "Repo: $HERE"
info "Steps: preflight -> claude-code -> skills$([[ $WITH_MCP == 1 ]] && echo ' -> mcp')\
$([[ $WITH_PLUGINS == 1 ]] && echo ' -> plugins') -> global-config$([[ $WITH_EXTRAS == 1 ]] && echo ' -> dev-tools')"

run() {
  local script="$HERE/scripts/$1"
  [[ -f "$script" ]] || die "Missing $script"
  bash "$script"
}

run 00-preflight.sh
run 10-claude-code.sh
run 20-skills.sh
[[ $WITH_MCP == 1 ]]     && run 30-mcp.sh
[[ $WITH_PLUGINS == 1 ]] && run 40-plugins.sh
run 50-global-config.sh
[[ $WITH_EXTRAS == 1 ]]  && run 60-dev-tools.sh

# Host git/GitHub helpers on PATH (run from any repo; push/PR/merge are host-only by design).
if [[ -w /opt/homebrew/bin ]]; then
  for u in git-pr-merge git-check; do
    ln -sfn "$HERE/$u" "/opt/homebrew/bin/$u" && ok "linked '$u' -> $HERE/$u"
  done
fi

step "Done"
ok "Setup complete."
cat <<'NEXT'

  Next steps:
    1. Open a NEW terminal (or run: exec zsh -l) so `claude` is on your PATH.
    2. Verify everything:           ./02-doctor.sh
    3. Read the guide:              docs/claude-code-setup.md
    4. Set up the isolated VM (recommended — the default runtime for real work):
         ./03-vm-up.sh                 # start + provision the always-on Colima VM
         ccvm my-app                  # VS Code on the host + Claude inside the VM
       Monitoring (Grafana, claude-monitor) lives INSIDE the VM. See docs/isolation.md.
    5. Quick / trusted task on the host instead? (the Mac app is fine for that)
         ./05-new-project.sh my-app --no-launch && cd ../my-app && claude
       then run /brainstorm to qualify the idea before any code.

NEXT

cat <<'MANUAL'
  Manual, one-time — multi-line prompts in the VM (ccvm runs Claude over SSH, so
  /terminal-setup can't run there). Set this up once on your HOST terminal:
    - Any terminal:  press  Ctrl+J  for a newline (Enter still submits).
    - iTerm2:        Settings -> Profiles -> Keys -> Key Mappings -> '+'
                     Shortcut: Shift+Return,  Action: Send Hex Codes,  Value: 0x0a
    - VS Code / Cursor / Zed / Alacritty:  run /terminal-setup once in a HOST Claude session.
    - Native (no setup): WezTerm, Ghostty, Kitty, Warp.
    Details: README.md -> "Multi-line prompts in the VM".

MANUAL
