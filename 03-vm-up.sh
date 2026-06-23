#!/usr/bin/env bash
# 03-vm-up.sh — bring up the always-on Colima Linux VM that is the DEFAULT isolated dev
# environment. It mounts ~/Projects (writable, virtiofs), runs Docker, and provisions
# Claude Code + the kit + the Grafana monitoring stack INSIDE the VM. Idempotent.
# Run once; then use `ccvm <project>` to work inside it. (Edit on the host, run in the VM.)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$HERE/scripts/lib.sh"

require_macos_arm
step "Colima VM — default isolated dev environment"

has brew || die "Homebrew required (see your Mac OS Setup doc)."
ensure_brew colima
ensure_brew docker
brew list --formula docker-compose >/dev/null 2>&1 || brew install docker-compose >/dev/null 2>&1 || true

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
info "Provisioning the VM (Claude Code, tools, skills, config, monitoring)..."
colima ssh -- bash "$HERE/scripts/vm-provision.sh" "$HERE" || warn "Provisioning reported issues — review the output above."

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
  local plist="$HOME/Library/LaunchAgents/com.${USER}.colima.plist" bin
  bin="$(command -v colima)"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.${USER}.colima</string>
  <key>ProgramArguments</key><array><string>${bin}</string><string>start</string></array>
  <key>RunAtLoad</key><true/>
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
EOF
