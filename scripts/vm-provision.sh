#!/usr/bin/env bash
# vm-provision.sh — provision the Colima Linux VM as a full Claude Code dev box.
# Runs INSIDE the VM (Ubuntu). Idempotent. Invoked by 03-vm-up.sh as:
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
# zsh: match the host's interactive shell (Claude's command tool still runs bash, so keep scripts
# POSIX/bash-portable). NB: we deliberately do NOT install bubblewrap/socat — they'd make Claude
# Code ENABLE its Bash sandbox, which then prompts "(unsandboxed)" per command; the VM is the
# boundary, so we run with NO inner sandbox (acceptEdits + a broad allow-list — see settings.vm.json).
# /doctor then shows a cosmetic "sandbox: missing bubblewrap" note — expected and harmless.
if has apt-get; then
  sudo apt-get update -qq >/dev/null 2>&1 || true
  sudo apt-get install -y -qq git jq curl ca-certificates build-essential zsh >/dev/null 2>&1 || warn "apt install issues"
fi
# Make zsh the interactive login shell for this user (matches the host).
if has zsh && [ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$(command -v zsh)" ]; then
  if sudo chsh -s "$(command -v zsh)" "$(id -un)" 2>/dev/null; then ok "zsh is the VM login shell"; else warn "could not chsh to zsh (cosmetic)."; fi
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

# --- Node.js (npx runtime for Context7/Playwright/sequential-thinking MCP + Node projects) --
if ! has node; then
  say "installing Node.js LTS…"
  if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - >/dev/null 2>&1 \
     && sudo apt-get install -y -qq nodejs >/dev/null 2>&1; then
    ok "node $(node -v 2>/dev/null)"
  else
    warn "Node install failed — npx-based MCP servers and Node projects won't work."
  fi
fi

# --- skills + global config + MCP: reuse the mounted kit (OS-agnostic steps) -----
if [[ -n "$KIT" && -d "$KIT" ]]; then
  say "installing skills + global config + MCP from the kit…"
  AUTO_YES=1 bash "$KIT/scripts/20-skills.sh"        || warn "skills step issues"
  AUTO_YES=1 bash "$KIT/scripts/50-global-config.sh" || warn "config step issues"
  AUTO_YES=1 bash "$KIT/scripts/30-mcp.sh" >/dev/null 2>&1 || warn "MCP registration issues"
else
  warn "kit dir not found ($KIT) — skipped skills/config (is ~/Projects mounted?)."
fi

# --- pre-mark onboarding so the FIRST interactive `claude` skips the login/theme wizard ----
# Auth comes from the CLAUDE_CODE_OAUTH_TOKEN that `ccvm` injects; without this flag the
# first interactive run shows the onboarding (login method + theme) even when authenticated.
cc_json="$HOME/.claude.json"
[[ -f "$cc_json" ]] || echo '{}' > "$cc_json"
if has jq; then
  tmp="$(mktemp)"
  if jq '.hasCompletedOnboarding=true | .theme=(.theme // "dark")' "$cc_json" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$cc_json" && ok "onboarding pre-marked (first interactive run skips login/theme; theme=dark)"
  else
    rm -f "$tmp"; warn "could not patch ~/.claude.json — first interactive run will show onboarding."
  fi
fi

# --- VM settings profile: the VM is the security boundary, so it runs the OPPOSITE posture to the
#     host — NO inner Bash sandbox + full autonomy via a BROAD allow-list (all Bash, file edits,
#     WebSearch/WebFetch, the MCP servers) under acceptEdits. Result: no authorization prompts,
#     without relying on the buggy --dangerously-skip-permissions flag. We write a REAL
#     ~/.claude/settings.json = (kit base * VM overlay) with the two allow-lists UNIONED, REGENERATED
#     every run so it stays in sync with the kit; the macOS host keeps the symlinked, locked-down profile.
base="$KIT/claude-config/settings.json"
overlay="$KIT/claude-config/settings.vm.json"
us="$HOME/.claude/settings.json"
if has jq && [[ -f "$base" && -f "$overlay" ]]; then
  tmp="$(mktemp)"
  if jq -s '(.[0].permissions.allow // []) as $ba | (.[1].permissions.allow // []) as $oa
            | (.[0] * .[1]) | .permissions.allow = (($ba + $oa) | unique)' \
        "$base" "$overlay" > "$tmp" 2>/dev/null; then
    rm -f "$us"; mv "$tmp" "$us"
    ok "VM settings profile written (sandbox off + broad allow-list = full autonomy; refreshed from the kit each run)"
  else
    rm -f "$tmp"; warn "could not build VM settings.json — keeping the symlinked host profile."
  fi
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
printf '  Authenticate once on the HOST:  ./04-vm-auth.sh   (claude setup-token -> host-only token; ccvm injects it)\n'
printf '  Grafana:      cd %s && make up   -> http://localhost:3000 on your Mac\n' "$otel"
