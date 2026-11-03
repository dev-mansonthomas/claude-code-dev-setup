#!/usr/bin/env bash
# 03-vm-up.sh — bring up the always-on Colima Linux VM that is the DEFAULT isolated dev
# environment. It mounts ~/Projects (writable, virtiofs), runs Docker, and provisions
# Claude Code + the kit + the Grafana monitoring stack INSIDE the VM. Idempotent.
# Run once; then use `ccvm <project>` to work inside it. (Edit on the host, run in the VM.)
#
# Options: none on the command line except --help. Behaviour is tuned with ENVIRONMENT VARIABLES
# (e.g. `SKILLS_AUTO_APPLY=1 ./03-vm-up.sh`); `./03-vm-up.sh --help` lists every one with its
# consequences, and the same list is recapped at the end of each run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"
# shellcheck source=scripts/vm-env.sh
source "$HERE/scripts/vm-env.sh"

usage() {
  cat <<EOF
03-vm-up.sh - bring up the always-on Colima VM and provision it (Claude Code, tools, skills, config).

USAGE
  ./03-vm-up.sh [-h | --help]
  VAR=value ./03-vm-up.sh            # e.g.  SKILLS_AUTO_APPLY=1 ./03-vm-up.sh

  The only command-line option is --help. Every other setting is an ENVIRONMENT VARIABLE, listed
  below with its consequences. The script is idempotent: re-running it re-provisions the VM in place.

WHAT IT DOES, IN ORDER
  1. Installs colima / docker CLI / docker-compose with Homebrew when missing (an existing docker
     CLI, e.g. Docker Desktop's, is reused).
  2. Starts Colima (vz + virtiofs, ~/Projects mounted writable) only if it is not already running.
     Sizing is automatic: 4 CPU / 8 GB, or 6 CPU / 12 GB when the Mac has more than 24 GB of RAM,
     plus a 60 GB disk. It applies only when Colima has to be started; a running VM is not resized.
  3. Provisions the VM (scripts/vm-provision.sh): Claude Code, language/tool chains, skills, MCP
     servers, plugins, global config, monitoring stack. Skill sources are fetched; updates are
     reported but NOT applied unless SKILLS_AUTO_APPLY=1 (see below).
  4. Links 'ccvm' into /opt/homebrew/bin and installs a LaunchAgent that starts Colima at login
     (~/Library/LaunchAgents/com.\$USER.colima.plist).

ENVIRONMENT VARIABLES
$(render_env_help)

NOT CONFIGURABLE FROM HERE
  - Pinned tool versions (Playwright MCP = PW_MCP_VERSION, Packer, kubeconform, delta, obscura, ...):
    edit scripts/versions.env or scripts/vm-provision.sh. An environment variable of the same name is
    ignored.
  - Git identity in the VM (GIT_USER_NAME / GIT_USER_EMAIL inside provisioning): taken from the Mac's
    'git config --global user.name / user.email', not from your environment. A VM-side identity that
    already exists is never overwritten.
  - Variables read by the provisioning sub-steps INSIDE the VM (CONTEXT7_API_KEY, COPY_MODE,
    BACKUP_DIR, SKILLS_SRC_DIR) are not forwarded: set them in the VM and re-run the step
    (e.g. scripts/30-mcp.sh). CONTEXT7_API_KEY is deliberately never forwarded: it would appear in
    the argument list of a process, readable with 'ps'.

AFTER IT RUNS
  ccvm <project>           open a project: VS Code on the Mac + a Claude session inside the VM
  ./04-vm-auth.sh          first time only: authenticate the VM
  skills-update            (inside the VM) review and apply waiting skill updates
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1 - every setting is an environment variable; see ./03-vm-up.sh --help"; exit 2 ;;
  esac
done
validate_env || exit 2

require_macos_arm
step "Colima VM — default isolated dev environment"

has brew || die "Homebrew required (see your Mac OS Setup doc)."
ensure_brew colima
# The host only needs a docker CLI — it talks to Colima's dockerd via the 'colima' context that
# `colima start` activates. If one already exists (e.g. Docker Desktop), reuse it: installing the
# 'docker' formula would be redundant AND fail at `brew link` (Docker Desktop owns the docker
# completion symlinks), aborting this script.
if has docker; then
  ok "docker CLI present: $(command -v docker) — Colima provides the daemon (colima context)"
else
  ensure_brew docker
fi
# docker compose: Docker Desktop ships it as a plugin; only install the standalone formula if absent.
if docker compose version >/dev/null 2>&1 || has docker-compose; then
  ok "docker compose available"
else
  NONINTERACTIVE=1 HOMEBREW_NO_ENV_HINTS=1 brew install docker-compose >/dev/null 2>&1 \
    || warn "docker-compose not installed (compose plugin is optional)."
fi

# RAM-aware sizing: 8GB on a 24GB Mac, 12GB if the host has more.
mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
host_gb=$(( mem_bytes / 1073741824 ))
if (( host_gb > 24 )); then VM_MEM=12; VM_CPU=6; else VM_MEM=8; VM_CPU=4; fi
info "Host RAM ${host_gb}GB → VM: ${VM_CPU} CPU / ${VM_MEM}GB / 60GB disk"

PROJECTS="$HOME/Projects"
mkdir -p "$PROJECTS"

if colima status >/dev/null 2>&1; then
  ok "Colima already running ($(colima version 2>/dev/null | head -1))."
else
  info "Starting Colima (vz + virtiofs; mounting $PROJECTS writable)..."
  colima start --vm-type vz --mount-type virtiofs \
    --cpu "$VM_CPU" --memory "$VM_MEM" --disk 60 \
    --mount "$PROJECTS:w"
fi

if docker info >/dev/null 2>&1; then ok "Docker (in VM) reachable."; else warn "Docker not reachable yet (give it a few seconds)."; fi

# Provision the VM. The kit lives under ~/Projects, so it's mounted at the same path inside.
# Pass the HOST's git identity so VM commits aren't anonymous — the VM inherits it by default.
info "Provisioning the VM (Claude Code, tools, skills, config, monitoring)..."
host_git_name="$(git config --global user.name 2>/dev/null || true)"
host_git_email="$(git config --global user.email 2>/dev/null || true)"
# Host environment reaches the VM ONLY through the documented variables (scripts/vm-env.sh,
# WHERE=vm) — never the rest of the environment, never secrets. Show what is forwarded.
vm_env=("GIT_USER_NAME=$host_git_name" "GIT_USER_EMAIL=$host_git_email")
while IFS= read -r fwd; do
  if [[ -n "$fwd" ]]; then vm_env+=("$fwd"); info "Forwarding to the VM: $fwd"; fi
done < <(forwarded_env_lines)
colima ssh -- env "${vm_env[@]}" \
  bash "$HERE/scripts/vm-provision.sh" "$HERE" || warn "Provisioning reported issues — review the output above."

# `ccvm` on PATH for the default workflow.
if [[ -w /opt/homebrew/bin ]]; then
  # Remove the legacy 'cc' launcher symlink if present — it collided with the C compiler.
  if [[ -L /opt/homebrew/bin/cc && "$(readlink /opt/homebrew/bin/cc)" == "$HERE/"* ]]; then
    rm -f /opt/homebrew/bin/cc && ok "removed legacy 'cc' symlink (it shadowed the system C compiler)"
  fi
  ln -sfn "$HERE/ccvm" /opt/homebrew/bin/ccvm && ok "linked 'ccvm' -> $HERE/ccvm"
fi

# Always-on: auto-start Colima at login via a LaunchAgent (best-effort).
install_launch_agent() {
  local plist="$HOME/Library/LaunchAgents/com.${USER}.colima.plist" bin bindir
  bin="$(command -v colima)"; bindir="$(dirname "$bin")"
  mkdir -p "$HOME/Library/LaunchAgents"
  # launchd runs with a MINIMAL PATH; colima needs limactl (in $bindir, e.g. /opt/homebrew/bin) on
  # PATH or `colima start` fails at login (exit 1). Set PATH explicitly; log stderr for debugging.
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.${USER}.colima</string>
  <key>ProgramArguments</key><array><string>${bin}</string><string>start</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>${bindir}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>/tmp/colima-launchagent.log</string>
</dict></plist>
PL
  launchctl unload "$plist" 2>/dev/null || true
  if launchctl load "$plist" 2>/dev/null; then ok "Always-on: Colima auto-starts at login ($plist)"; else warn "Could not load LaunchAgent (optional; remove $plist to undo)."; fi
}
install_launch_agent

ok "VM ready."
cat <<EOF

  Default workflow — everything runs IN the VM:
    ccvm <project>     # opens VS Code on the host + a Claude session inside the VM
    ccvm               # just shell into the VM (at ~/Projects)
    ./05-new-project.sh <name>   # scaffolds, then auto-launches ccvm (VS Code + VM)

  First time only: authenticate the VM from the host:  ./04-vm-auth.sh
                   (runs 'claude setup-token' and stores the token host-side for ccvm to inject).
  Monitoring (Grafana) lives in the VM:  ccvm  →  cd ~/claude-code-otel && make up
                   → open http://localhost:3000 on your Mac (admin/admin; the port is forwarded).

  iTerm2 (host) - one-time, for the ccvm-over-SSH workflow:
    - Multi-line prompt: press Ctrl+J for a newline (Enter submits). For Shift+Enter, map it:
      Settings -> Profiles -> Keys -> Key Mappings -> '+' -> Shift+Return, Send Hex Codes, 0x0a
    - Completion bell (Claude beeps when done / needs input, over SSH):
      Settings -> Profiles -> Terminal -> uncheck "Silence bell"
    Details: README.md -> "Multi-line prompts in the VM".

  Environment variables for this script (VAR=value ./03-vm-up.sh) - full consequences: ./03-vm-up.sh --help
EOF
render_env_recap
cat <<'EOF'
  Skill updates are never applied unattended unless SKILLS_AUTO_APPLY=1: inside the VM run
  'skills-update' to review and apply what is waiting.
EOF
