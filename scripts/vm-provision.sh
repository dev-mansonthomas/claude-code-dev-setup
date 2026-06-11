#!/usr/bin/env bash
# vm-provision.sh — provision the Colima Linux VM as a full Claude Code dev box.
# Runs INSIDE the VM (Ubuntu). Idempotent. Invoked by vm-up.sh as:
#     vm-provision.sh <KIT_DIR>
# Installs Claude Code + git/jq/gitleaks/uv, reuses the (mounted) kit for skills + global
# config, installs claude-monitor, and clones claude-code-otel for in-VM Grafana monitoring.
set -uo pipefail
KIT="${1:-}"

say(){  printf '\033[34m•\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m!\033[0m %s\n' "$*" >&2; }
has(){  command -v "$1" >/dev/null 2>&1; }

say "Provisioning the VM as a Claude Code dev box…"

# --- base tools ------------------------------------------------------------
if has apt-get; then
  sudo apt-get update -qq >/dev/null 2>&1 || true
  sudo apt-get install -y -qq git jq curl ca-certificates build-essential >/dev/null 2>&1 || warn "apt install issues"
fi

# --- uv --------------------------------------------------------------------
if ! has uv; then
  say "installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install issue"
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- gitleaks (Linux binary; powers the secret-scan hooks) -----------------
if ! has gitleaks; then
  say "installing gitleaks…"
  ver="8.30.1"; arch="$(uname -m)"; case "$arch" in aarch64|arm64) gla="arm64";; *) gla="x64";; esac
  t="$(mktemp -d)"
  if curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${ver}/gitleaks_${ver}_linux_${gla}.tar.gz" -o "$t/g.tgz" 2>/dev/null \
     && tar -xzf "$t/g.tgz" -C "$t" gitleaks 2>/dev/null \
     && sudo install "$t/gitleaks" /usr/local/bin/gitleaks 2>/dev/null; then
    ok "gitleaks $ver"
  else
    warn "gitleaks install failed (the secret hook will fail-open)."
  fi
  rm -rf "$t"
fi

# --- Claude Code (native installer works on Linux) ------------------------
if ! has claude && [[ ! -x "$HOME/.local/bin/claude" ]]; then
  say "installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || warn "Claude Code install issue"
fi
export PATH="$HOME/.local/bin:$PATH"

# --- skills + global config: reuse the mounted kit (OS-agnostic steps) -----
if [[ -n "$KIT" && -d "$KIT" ]]; then
  say "installing skills + global config from the kit…"
  AUTO_YES=1 bash "$KIT/scripts/20-skills.sh"       || warn "skills step issues"
  AUTO_YES=1 bash "$KIT/scripts/50-global-config.sh" || warn "config step issues"
else
  warn "kit dir not found ($KIT) — skipped skills/config (is ~/Projects mounted?)."
fi

# --- usage gauge -----------------------------------------------------------
if has uv; then uv tool install claude-monitor >/dev/null 2>&1 || uv tool upgrade claude-monitor >/dev/null 2>&1 || true; fi

# --- monitoring stack (Grafana) lives in the VM (no second VM) -------------
otel="$HOME/claude-code-otel"
if [[ -d "$otel/.git" ]]; then
  ok "claude-code-otel already cloned ($otel)"
elif git clone --depth 1 https://github.com/ColeMurray/claude-code-otel.git "$otel" >/dev/null 2>&1; then
  ok "claude-code-otel cloned ($otel)"
else
  warn "could not clone claude-code-otel."
fi

ok "VM provisioned."
printf '  Log in once:  claude            (or on host: claude setup-token -> export CLAUDE_CODE_OAUTH_TOKEN)\n'
printf '  Grafana:      cd %s && make up   -> http://localhost:3000 on your Mac\n' "$otel"
