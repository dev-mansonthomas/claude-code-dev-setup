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
# boundary, so we run with NO inner sandbox + a broad allow-list (see settings.vm.json); the primary
# launcher `ccvm` starts Claude in `auto` mode via the CLI flag (settings' defaultMode is a fallback).
# /doctor then shows a cosmetic "sandbox: missing bubblewrap" note — expected and harmless.
if has apt-get; then
  sudo apt-get update -qq >/dev/null 2>&1 || true
  # python3-venv gives stdlib `python3 -m venv` its `ensurepip` (Ubuntu splits it out); python3-pip
  # for a system pip. `uv` (installed later) is still the recommended env tool, but many projects
  # (esp. ones migrated from other agents) assume plain `python -m venv`.
  sudo apt-get install -y -qq git jq curl ca-certificates build-essential zsh shellcheck python3-venv python3-pip >/dev/null 2>&1 || warn "apt install issues"
fi
# Make zsh the interactive login shell for this user (matches the host).
if has zsh && [ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$(command -v zsh)" ]; then
  if sudo chsh -s "$(command -v zsh)" "$(id -un)" 2>/dev/null; then ok "zsh is the VM login shell"; else warn "could not chsh to zsh (cosmetic)."; fi
fi

# --- git identity: inherit the host's by default (so VM commits aren't anonymous) ----------
# 03-vm-up.sh passes GIT_USER_NAME/GIT_USER_EMAIL from the host's global git config. We set them in
# the VM only if unset, so a deliberate VM-side identity is never clobbered.
if has git; then
  if [ -n "${GIT_USER_NAME:-}" ] && [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    git config --global user.name "$GIT_USER_NAME"
  fi
  if [ -n "${GIT_USER_EMAIL:-}" ] && [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
  fi
  un="$(git config --global user.name 2>/dev/null)"
  if [ -n "$un" ]; then
    ok "git identity: $un <$(git config --global user.email 2>/dev/null)>"
  else
    warn "git identity still unset (host had none) — set it in the VM: git config --global user.name/email"
  fi
fi

# --- network / debug tooling (all CLI, text output the agent can read) -----
# DNS (dig/host/nslookup), port reachability (telnet, nc), path+latency (ping/traceroute/mtr),
# packet capture (tcpdump, and tshark = Wireshark's CLI — the closest thing the agent can use;
# capture needs sudo/CAP_NET_RAW, which `lima` has), listening sockets (ss/netstat/lsof), a direct
# TLS/cert inspection (openssl). (redis-cli comes from the official Redis repo below — 8.x.) We still
# SKIP socat — like bubblewrap it makes Claude Code re-enable its Bash sandbox.
# DEBIAN_FRONTEND=noninteractive silences tshark's "allow non-root capture?" debconf prompt
# (default no; use `sudo tshark`/`sudo tcpdump`).
if has apt-get; then
  say "installing network/debug tools (dig, telnet, nc, tcpdump, tshark, …)…"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    dnsutils telnet netcat-openbsd iputils-ping traceroute mtr-tiny \
    tcpdump tshark iproute2 net-tools lsof openssl \
    >/dev/null 2>&1 || warn "some network/debug tools failed to install"
fi

# --- redis-cli 8.x (official Redis apt repo; Ubuntu ships only 7.0.x) ----------------------
# Projects target Redis 8.x (Search/JSON/Functions) — keep the CLI current. CLI only; the SERVER
# always runs in Docker per project. Skips if 8.x is already present.
if has apt-get && ! redis-cli --version 2>/dev/null | grep -q ' 8\.'; then
  say "installing redis-cli 8.x (official Redis apt repo)…"
  codename="$(awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release 2>/dev/null)"
  curl -fsSL https://packages.redis.io/gpg 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg 2>/dev/null
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${codename:-noble} main" \
    | sudo tee /etc/apt/sources.list.d/redis.list >/dev/null
  sudo apt-get update -qq >/dev/null 2>&1 || true
  if sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-tools >/dev/null 2>&1; then
    ok "redis-cli $(redis-cli --version 2>/dev/null | awk '{print $2}')"
  else
    warn "redis-cli 8.x install failed (kept whatever was there)."
  fi
fi

# --- extra debug tooling (general-purpose, CLI) ----------------------------
# strace (syscalls of a stuck/failing process), htop + the procps suite (ps/top/free/vmstat),
# nmap (port scan, broader than telnet/nc), httpie (readable HTTP client), yq (jq-for-YAML).
if has apt-get; then
  say "installing debug tools (strace, htop, nmap, httpie, yq)…"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    strace htop procps nmap httpie yq \
    >/dev/null 2>&1 || warn "some debug tools failed to install"
fi

# grpcurl: probe gRPC endpoints. Not in apt — fetch the static binary from GitHub (like gitleaks).
if ! has grpcurl; then
  say "installing grpcurl…"
  gver="1.9.3"; case "$(uname -m)" in aarch64|arm64) garch="arm64";; *) garch="x86_64";; esac
  gt="$(mktemp -d)"
  if curl -fsSL "https://github.com/fullstorydev/grpcurl/releases/download/v${gver}/grpcurl_${gver}_linux_${garch}.tar.gz" -o "$gt/g.tgz" 2>/dev/null \
     && tar -xzf "$gt/g.tgz" -C "$gt" grpcurl 2>/dev/null \
     && sudo install "$gt/grpcurl" /usr/local/bin/grpcurl 2>/dev/null; then
    ok "grpcurl $gver"
  else
    warn "grpcurl install failed (optional)."
  fi
  rm -rf "$gt"
fi

# --- fd (fast, user-friendly file finder; used by search skills like file-search) -----------
# Ubuntu ships it as the 'fd-find' package with the binary named 'fdfind' (name clash with
# another package), so symlink 'fd' — that's the name tools and skills actually call.
if ! has fd && has apt-get; then
  say "installing fd (fd-find)…"
  if sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fd-find >/dev/null 2>&1; then
    fdbin="$(command -v fdfind || true)"
    if [ -n "$fdbin" ]; then sudo ln -sfn "$fdbin" /usr/local/bin/fd; fi
    ok "fd (fd-find → /usr/local/bin/fd)"
  else
    warn "fd-find install failed."
  fi
fi

# --- uv --------------------------------------------------------------------
if ! has uv; then
  say "installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1 || warn "uv install issue"
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
# ruff — the Python linter/formatter that the global CLAUDE.md defaults to (and settings.json already
# allow-lists as `Bash(ruff:*)`). Install it as a uv tool so `ruff` is on PATH for any project.
# mypy/pytest stay per-project (they need the project's deps), added there via `uv add --dev`.
if has uv && ! has ruff; then
  say "installing ruff (Python linter/formatter, uv tool)…"
  uv tool install ruff >/dev/null 2>&1 || warn "ruff install failed (fallback: uvx ruff)."
fi

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

# --- browser testing: Playwright browsers + system libs (web / SPA testing & screenshots) -----
# Chromium/Firefox/WebKit need system libraries to launch (libnss3, libgbm1, libasound2t64,
# gstreamer for webkit, fonts…) that only apt/root can install. `playwright install --with-deps`
# installs the browser binaries (into ~/.cache/ms-playwright, reused by the Playwright MCP and any
# project's @playwright/test) AND those libs via sudo apt — self-maintaining across Ubuntu/Chromium
# versions (vs a hardcoded lib list). corepack enables pnpm/yarn for React+Vite / Angular. CHROME_BIN
# points Angular's `ng test` (Karma ChromeHeadless) at Playwright's Chromium — on arm64 there's no
# system google-chrome (amd64-only) and Ubuntu's chromium is a snap, so we reuse Playwright's build.
# Fonts (emoji + CJK) stop screenshots rendering international text as boxes.
if has npx; then
  say "installing Playwright browsers (chromium/firefox/webkit) + system libs…"
  npx --yes playwright@latest install --with-deps chromium firefox webkit >/dev/null 2>&1 \
    || warn "Playwright browser/deps install failed (browser tests may not launch)."
  sudo corepack enable >/dev/null 2>&1 || true
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fonts-noto-color-emoji fonts-noto-cjk >/dev/null 2>&1 || true
  # Expose Playwright's Chromium as a stable system Chrome (CHROME_BIN) for Angular Karma / ng test.
  chrome_bin="$(find "$HOME/.cache/ms-playwright" -maxdepth 3 -path '*chromium-*/chrome-linux/chrome' -type f 2>/dev/null | sort -V | tail -1)"
  if [ -n "$chrome_bin" ]; then
    sudo ln -sfn "$chrome_bin" /usr/local/bin/chrome
    echo 'export CHROME_BIN=/usr/local/bin/chrome' | sudo tee /etc/profile.d/chrome-bin.sh >/dev/null
    ok "CHROME_BIN -> Playwright Chromium (Angular Karma / ng test)"
  fi
fi

# --- JVM toolchain: OpenJDK 21 + Maven 3.9 (Spring / Jedis / Java projects) -----------------
# Ubuntu ships OpenJDK 21 (= Java 21, parity with projects' Temurin-21 image) but only Maven 3.8.7,
# so Maven 3.9.x comes from the Apache binary. JAVA_HOME is exported (login shells) for Maven/Gradle.
if has apt-get && ! has java; then
  say "installing OpenJDK 21…"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-21-jdk >/dev/null 2>&1 || warn "openjdk-21-jdk install failed"
fi
if has java; then
  jh="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  echo "export JAVA_HOME=$jh" | sudo tee /etc/profile.d/jdk.sh >/dev/null
fi
if has java && ! has mvn; then
  say "installing Maven 3.9 (Apache binary; apt only has 3.8.x)…"
  mver="3.9.16"; mt="$(mktemp -d)"
  # archive.apache.org keeps every release (dlcdn drops old ones -> 404 once a 3.9.x rotates).
  if curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${mver}/binaries/apache-maven-${mver}-bin.tar.gz" -o "$mt/m.tgz" 2>/dev/null \
     && sudo tar -xzf "$mt/m.tgz" -C /opt 2>/dev/null \
     && sudo ln -sfn "/opt/apache-maven-${mver}/bin/mvn" /usr/local/bin/mvn; then
    ok "maven $mver"
  else
    warn "Maven 3.9 install failed (fallback: sudo apt-get install -y maven → 3.8.x)."
  fi
  rm -rf "$mt"
fi

# --- Lua tooling: luacheck (lint Redis Functions / Lua scripts) -----------------------------
# lua-language-server / stylua aren't in apt; luacheck (the standard Lua linter) installs via luarocks.
if has apt-get && ! has luacheck; then
  say "installing Lua + luacheck (linter for Redis Lua / Functions)…"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lua5.4 luarocks >/dev/null 2>&1 || warn "lua/luarocks install failed"
  sudo luarocks install luacheck >/dev/null 2>&1 || warn "luacheck install failed"
fi

# --- OpenTofu (Terraform-compatible IaC) — VALIDATE-ONLY in the VM --------------------------
# The VM runs the credential-free build-time checks — `tofu fmt -check`, `tofu init -backend=false`,
# `tofu validate`. `tofu plan/apply` need cloud creds + backend state, so they stay on the HOST
# (deploy side). Static binary from GitHub releases, like grpcurl/gitleaks.
if ! has tofu; then
  say "installing OpenTofu (tofu — validate/fmt in the VM; plan/apply stay on the host)…"
  tofuver="1.12.3"; case "$(uname -m)" in aarch64|arm64) tofuarch="arm64";; *) tofuarch="amd64";; esac
  tft="$(mktemp -d)"
  if curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${tofuver}/tofu_${tofuver}_linux_${tofuarch}.tar.gz" -o "$tft/t.tgz" 2>/dev/null \
     && tar -xzf "$tft/t.tgz" -C "$tft" tofu 2>/dev/null \
     && sudo install "$tft/tofu" /usr/local/bin/tofu 2>/dev/null; then
    ok "OpenTofu $tofuver"
  else
    warn "OpenTofu install failed (optional; IaC validation won't run in the VM)."
  fi
  rm -rf "$tft"
fi

# --- Go toolchain (official tarball — apt lags; go.dev/VERSION is always the latest stable) --
if ! has go; then
  gover="$(curl -fsSL 'https://go.dev/VERSION?m=text' 2>/dev/null | head -1)"
  case "$(uname -m)" in aarch64|arm64) goarch="arm64";; *) goarch="amd64";; esac
  if [ -n "$gover" ]; then
    say "installing Go ($gover)…"
    gt="$(mktemp -d)"
    if curl -fsSL "https://go.dev/dl/${gover}.linux-${goarch}.tar.gz" -o "$gt/go.tgz" 2>/dev/null \
       && sudo rm -rf /usr/local/go \
       && sudo tar -C /usr/local -xzf "$gt/go.tgz" 2>/dev/null; then
      # shellcheck disable=SC2016  # $PATH/$HOME are meant to stay literal — they expand at login
      printf 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin\n' | sudo tee /etc/profile.d/go.sh >/dev/null
      ok "Go $gover (/usr/local/go)"
    else
      warn "Go install failed (optional)."
    fi
    rm -rf "$gt"
  else
    warn "could not resolve the latest Go version (skipping)."
  fi
fi

# --- Rust toolchain (rustup — the canonical installer; installs the current stable) ---------
if ! has cargo && ! has rustc; then
  say "installing Rust (rustup, stable)…"
  if curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs 2>/dev/null | sh -s -- -y --profile default --no-modify-path >/dev/null 2>&1; then
    # System profile.d entry so every login shell (zsh/bash) picks up ~/.cargo/bin per user.
    # shellcheck disable=SC2016  # $HOME is meant to stay literal — it expands at login
    printf '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"\n' | sudo tee /etc/profile.d/cargo.sh >/dev/null
    ok "Rust (rustup) — rustc/cargo/clippy/rustfmt in ~/.cargo/bin"
  else
    warn "Rust install failed (optional)."
  fi
fi

# --- .NET SDK (Microsoft dotnet-install.sh; --channel LTS = latest LTS, no version pin) ------
if ! has dotnet; then
  say "installing .NET SDK (LTS)…"
  dt="$(mktemp -d)"
  if curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$dt/dotnet-install.sh" 2>/dev/null \
     && chmod +x "$dt/dotnet-install.sh" \
     && sudo "$dt/dotnet-install.sh" --channel LTS --install-dir /usr/local/dotnet --no-path >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # $PATH is meant to stay literal — it expands at login
    printf 'export DOTNET_ROOT=/usr/local/dotnet\nexport DOTNET_CLI_TELEMETRY_OPTOUT=1\nexport PATH=$PATH:/usr/local/dotnet\n' \
      | sudo tee /etc/profile.d/dotnet.sh >/dev/null
    ok ".NET SDK LTS (/usr/local/dotnet)"
  else
    warn ".NET SDK install failed (optional)."
  fi
  rm -rf "$dt"
fi

# --- obscura (stealth headless browser for AI agents/scraping — prebuilt Rust binary, no npm) --
# FALLBACK for web research when a site blocks/filters normal fetch, or for JS-heavy pages. Prebuilt
# binary (no build, no npm, no curl|bash). VM-only on purpose: it runs untrusted page JS via V8, so
# the isolated VM is the right place. Ships its own MCP server, registered by 30-mcp.sh.
# PINNED to an exact version + SHA256 — obscura is a third-party project and publishes no checksums,
# so we verify the bytes before installing. To bump: set OBSCURA_VERSION and recompute both SHA256s
# (`shasum -a 256 obscura-<arch>-linux-stealth.tar.gz`). The notifier below flags newer releases.
OBSCURA_VERSION="0.2.0"
OBSCURA_SHA256_AARCH64="d9b55448043815872d6fdc9d51aca7efd4055abff41fe3dd3fb512718c746bee"
OBSCURA_SHA256_X86_64="4b0fe0ff32a2e17e33b1e3d67bfb06e8f4d875bdffa86aa766277232422dfde7"
if ! has obscura; then
  case "$(uname -m)" in
    aarch64|arm64) obarch="aarch64"; obsha="$OBSCURA_SHA256_AARCH64" ;;
    *)             obarch="x86_64";  obsha="$OBSCURA_SHA256_X86_64" ;;
  esac
  say "installing obscura ${OBSCURA_VERSION} (stealth headless browser, ${obarch}-linux)…"
  ot="$(mktemp -d)"
  url="https://github.com/h4ckf0r0day/obscura/releases/download/v${OBSCURA_VERSION}/obscura-${obarch}-linux-stealth.tar.gz"
  if curl -fsSL "$url" -o "$ot/o.tgz" 2>/dev/null; then
    got="$(sha256sum "$ot/o.tgz" 2>/dev/null | awk '{print $1}')"
    if [ "$got" != "$obsha" ]; then
      warn "obscura SHA256 mismatch (got ${got:-none}, want $obsha) — NOT installing (tampering or stale pin)."
    elif tar -xzf "$ot/o.tgz" -C "$ot" 2>/dev/null; then
      obin="$(find "$ot" -type f -name obscura 2>/dev/null | head -1)"
      if [ -n "$obin" ] && sudo install "$obin" /usr/local/bin/obscura 2>/dev/null; then
        ok "obscura ${OBSCURA_VERSION} installed ($(/usr/local/bin/obscura --version 2>/dev/null | head -1))"
      else
        warn "obscura binary not found in tarball / install failed (skipping)."
      fi
    else
      warn "obscura extract failed (skipping)."
    fi
  else
    warn "obscura download failed (optional; stealth-browser fallback unavailable)."
  fi
  rm -rf "$ot"
fi
# obscura update notifier — warn (never auto-update) when a newer release than the pin exists, so the
# maintainer reviews the changelog and bumps OBSCURA_VERSION + the two SHA256s above deliberately.
if has curl && has jq; then
  obs_latest="$(curl -fsSL https://api.github.com/repos/h4ckf0r0day/obscura/releases/latest 2>/dev/null | jq -r '.tag_name // empty' | sed 's/^v//')"
  if [ -n "$obs_latest" ] && [ "$obs_latest" != "$OBSCURA_VERSION" ]; then
    warn "obscura $obs_latest is available (pinned: $OBSCURA_VERSION). Review it, then bump OBSCURA_VERSION + the two SHA256 pins in scripts/vm-provision.sh."
  fi
fi

# --- skills + global config + MCP + plugins: reuse the mounted kit (OS-agnostic steps) -----
if [[ -n "$KIT" && -d "$KIT" ]]; then
  say "installing skills + global config + MCP + plugins from the kit…"
  AUTO_YES=1 bash "$KIT/scripts/20-skills.sh"        || warn "skills step issues"
  AUTO_YES=1 bash "$KIT/scripts/50-global-config.sh" || warn "config step issues"
  AUTO_YES=1 bash "$KIT/scripts/30-mcp.sh" >/dev/null 2>&1 || warn "MCP registration issues"
  AUTO_YES=1 bash "$KIT/scripts/40-plugins.sh" >/dev/null 2>&1 || warn "plugin install issues (e.g. superpowers)"
else
  warn "kit dir not found ($KIT) — skipped skills/config (is ~/Projects mounted?)."
fi

# --- kit host-utility commands on PATH: vm-clean + skill-activate --------------------------
# vm-clean reclaims space on the small root FS; skill-activate powers per-project /skills-review.
if [[ -n "$KIT" && -f "$KIT/scripts/vm-clean.sh" ]]; then
  sudo ln -sfn "$KIT/scripts/vm-clean.sh" /usr/local/bin/vm-clean && ok "linked 'vm-clean'"
fi
if [[ -n "$KIT" && -f "$KIT/scripts/skill-activate.sh" ]]; then
  sudo ln -sfn "$KIT/scripts/skill-activate.sh" /usr/local/bin/skill-activate && ok "linked 'skill-activate'"
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
#     WebSearch/WebFetch, the MCP servers). settings.json sets defaultMode=acceptEdits as a fallback,
#     but `ccvm` launches Claude with `--permission-mode auto` (the CLI flag overrides defaultMode),
#     so `auto` is the actual posture of the primary workflow. Result: no authorization prompts,
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
