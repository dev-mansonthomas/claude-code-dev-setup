# claude-code-dev-setup

Reproducible, professional **Claude Code** setup for building real applications —
tuned for a Redis Solution Architect's workflow: qualify the need → spec →
test-first → performance & security aware → ship with clean git → document for
both humans and agents.

Run one command on a fresh Mac (or your second MacBook) and get the same
Claude Code environment: the CLI, the right Skills, useful MCP servers, a strong
global `CLAUDE.md`, a secret-scanning git guard, workflow slash commands, and a
project scaffolder.

**Real work runs inside an isolated VM by default** — so a malicious dependency, a
prompt-injection, or a runaway agent can't reach your SSH keys, keychain, cloud tokens, or
the rest of your Mac. The bare host (Mac app) stays for quick, trusted tasks. See
[Security model](#security-model--why-this-exists).

> New to all this? Read **[docs/claude-code-setup.md](docs/claude-code-setup.md)** —
> a zero-assumed-knowledge guide that takes you from install to top-level.

---

## Security model — why this exists

Claude Code is powerful, and "powerful" cuts both ways: the agent — or a malicious npm/pip
package it installs, or a prompt-injection in a page it reads — runs with **your** user's rights.
On the bare host that means it can read `~/.ssh`, your macOS keychain, cloud/API tokens and
browser sessions, and delete anything you can. The point of this kit is to **keep that blast
radius off your Mac.**

Two tiers — pick per task:

| | Where Claude runs | Use it for | Exposure |
|---|---|---|---|
| **Host** (Mac app / `claude`) | your macOS user account | trivial, trusted, low-risk edits & questions | **full** access to your account — only when you trust the prompt and aren't running untrusted code/deps |
| **VM mode** *(default)* | inside the Colima Linux VM | real work: untrusted deps, builds, autonomous runs (`acceptEdits` + broad allow-list) | confined to the VM **+** the mounted `~/Projects` |

**What VM mode protects:** credential theft (SSH keys, keychain, cloud/API tokens, browser
cookies) and destructive actions (mass deletion, ransomware-style writes) **can't reach the host** —
the VM is a separate kernel with no view of your home directory except the one folder you mount.

**What it does *not* (yet) protect:** the `~/Projects` mount is **writable**, so a compromised VM
can still tamper with your project files (mitigation: they're in git and pushed), and **outbound
network is currently unrestricted** — an attacker could exfiltrate whatever the VM can read.
Closing that path is the [Network firewall](#network-firewall-planned) work below.

Set the VM up with **[`./03-vm-up.sh`](#run-everything-in-an-isolated-vm-default)**; full walkthrough
and caveats in **[docs/isolation.md](docs/isolation.md)**.

---

## The workflow — build in the VM, ship & deploy from the host

The daily loop (qualify before you code):

**`/brainstorm` → `/spec` → `/plan-feature` (TDD) → implement → `/code-review` + `/security-review` → `/ship` → deploy → `/doc-sync`**

…and a hard split of **where** each step runs, which falls straight out of the
[security model](#security-model--why-this-exists):

| Step | In the **VM** (no credentials) | On the **host** (has credentials) |
|---|---|---|
| edit · test · **build Docker images** | ✅ | |
| local git (branch, commit) | ✅ | |
| `git push` · PR · merge | | ✅ — Claude prints the exact commands |
| **deploy** (terraform · push image · `gcloud run deploy`) | | ✅ — `./deploy/gcp-deploy.sh` |

**Why this split?**

- **Build in the VM.** Building runs untrusted code — third-party deps, postinstall scripts, your
  own work-in-progress. Confining it to the VM means a malicious dependency can't reach your SSH
  keys, keychain, or cloud tokens. Docker runs *inside* the VM (Colima), so images build there too.
- **Push & deploy from the host.** Pushing, PRs, and deploying need real credentials (GitHub;
  GCP/AWS/Azure) — and those live **only on the host**. Claude in the VM never holds them: it makes
  local commits and **prints** the host commands, and for a deploy it **generates
  `deploy/gcp-deploy.sh`** for you to review and run on the host. (Best case: keyless deploy via
  GitHub Actions OIDC / Workload Identity Federation — then cloud creds live on *no* laptop at all.)

So a change flows: **build + commit in the VM → you `git push` / PR / merge on the host → you run
`./deploy/gcp-deploy.sh` on the host.** The credential boundary is never crossed. Details:
[docs/isolation.md](docs/isolation.md).

---

## What you need first (prerequisites)

You almost certainly have these from the "Mac OS Setup" guide. The setup script
checks and installs the small extras for you.

| Tool | Have it? | If not |
|------|----------|--------|
| macOS (Apple Silicon) | — | this kit targets arm64 Macs |
| Homebrew | `brew --version` | [brew.sh](https://brew.sh) |
| Git | `git --version` | `xcode-select --install` |
| Node.js (for `npx`) | `node --version` | `nvm install --lts` |
| VS Code (or your editor) | `code --version` | to watch the code while Claude writes it — `brew install --cask visual-studio-code` |
| A Claude Pro/Max/Team/Enterprise/Console account | — | required for Claude Code |

The script installs `gh`, `gitleaks`, `uv`, and `jq` via Homebrew if missing.

## Quickstart

```bash
# 1. get this repo  (already have it? just `cd` in and skip the clone)
git clone https://github.com/dev-mansonthomas/claude-code-dev-setup.git
cd claude-code-dev-setup

# 2. install & configure everything (idempotent, NON-interactive by default).
#    Want a Context7 API key? export CONTEXT7_API_KEY=... first (optional; else keyless).
#    Prefer to confirm each step? add --interactive.
./01-setup.sh

# 3. open a NEW terminal so `claude` is on your PATH
exec zsh -l                      # (or just open a new tab/window)

# 4. log in to Claude Code (first run only), then verify
claude                           # complete the one-time login, then quit
./02-doctor.sh                      # expect mostly green: CLI, linked config, skills, MCP
```

That's it. `01-setup.sh` prepares the **host baseline**:

1. **Preflight** — check macOS/brew/git/node, install `gh` `gitleaks` `uv` `jq`.
2. **Claude Code** — install the CLI via the official native installer.
3. **Skills** — install the Redis SA + official Redis + frontend-design skills.
4. **MCP servers** — add Context7, Playwright, Sequential-Thinking (user scope).
5. **Plugins** — show how to add marketplaces (interactive, optional).
6. **Global config** — link `CLAUDE.md`, `settings.json`, the secret-guard hook,
   and the workflow slash commands into `~/.claude` (your existing files are
   backed up first).
7. **Dev tooling (host) — OFF by default.** Monitoring (`claude-monitor`, the OTEL/Grafana
   stack) and Claude Squad now run **inside the VM**, so the host stays lean. Want them on the
   host too? `./01-setup.sh --with-extras`. The status line (ccstatusline) and telemetry are wired
   into `settings.json` either way. See [docs/tooling-setup.md](docs/tooling-setup.md).

**Then set up the VM** — the recommended runtime for real work (one time):
```bash
./03-vm-up.sh
```
See [Run everything in an isolated VM](#run-everything-in-an-isolated-vm-default) below.

### Options

```bash
./01-setup.sh --copy         # copy config into ~/.claude instead of symlinking
./01-setup.sh --no-mcp       # skip MCP registration
./01-setup.sh --no-plugins   # skip the (optional) plugins info step
./01-setup.sh --with-extras  # ALSO install host monitoring/multi-project tooling (default: in the VM only)
./01-setup.sh --interactive  # confirm before each step (default: non-interactive)
```

By default config is **symlinked** from this repo into `~/.claude`, so
`git pull` here keeps both your MacBooks in sync.

## Run everything in an isolated VM (default)

For strong isolation, run Claude + tools + Docker inside an **always-on Colima Linux VM**.
You edit on the host (`~/Projects` is mounted in); Claude, builds, tests and the Grafana
stack run **in the VM** — a compromised dep/agent can't touch `~/.ssh`, your keychain, or the
rest of macOS.
```bash
./03-vm-up.sh                 # once: start + provision the VM  (make vm-up)
ccvm my-app                  # open VS Code on the host + a Claude session inside the VM
```
`05-new-project.sh` auto-launches `ccvm` after scaffolding; monitoring (Grafana) runs in the same
VM (no second VM). Inside the VM, Claude runs in `acceptEdits` with a broad allow-list — it
auto-accepts edits and auto-runs the dev toolchain, so you work hands-off (see [docs/isolation.md](docs/isolation.md)).
Full guide + caveats: **[docs/isolation.md](docs/isolation.md)**.

### Authenticate the VM once (`CLAUDE_CODE_OAUTH_TOKEN`)

Claude in the VM has no browser, so authenticate it with a long-lived token generated on the
**host** (this needs a Claude Pro/Max/Team/Enterprise subscription). One command does it:
```bash
./04-vm-auth.sh           # runs `claude setup-token`, then stores the token host-side (chmod 600)
```
Under the hood that is just:
```bash
claude setup-token        # on the HOST: opens a browser, then prints an sk-ant-oat01-… token (copy it)
mkdir -p ~/.config/claude-code-dev-setup && umask 077
pbpaste > ~/.config/claude-code-dev-setup/oauth-token    # paste the copied token here (host-only, chmod 600)
```
`ccvm` reads that file and injects the token into each VM session, so it **stays on the host and is
never written into the VM image or under `~/Projects`** — it can't be committed. Rotate by re-running
`claude setup-token`; revoke at the [Claude Console](https://console.anthropic.com).
*(Simpler but less safe: `export CLAUDE_CODE_OAUTH_TOKEN=…` in the VM's `~/.profile` — that persists the
secret inside the VM. Or just run `claude` once inside the VM and complete the interactive login.)*

Now that everything runs in the VM, the **host** copies of the monitoring stack are redundant — see
[docs/isolation.md → Trim the host](docs/isolation.md#trim-the-host-to-vm-only-optional).

## Network firewall (planned)

> **Status: not yet implemented — VM egress is open today.** The VM needs outbound internet to
> install packages, so for now it can reach the whole internet. Host isolation already protects your
> credentials and files; this section closes the remaining **exfiltration** path — a compromised dep
> sending what it can read (chiefly the mounted `~/Projects`) off-box.

**What a firewall can and can't do.** An egress firewall doesn't judge *intent* — it can't look at a
request and decide it's malicious. It judges **destination**: it flips the VM from "can reach all of
the internet" to "can reach only a handful of known hosts; everything else is dropped." That kills
the common case — automated supply-chain malware that phones home to an attacker-controlled server —
for almost no cost. It does **not** stop a determined attacker who abuses an *allowed* host (e.g.
pushing data to their own GitHub repo): **a trusted destination is not a trusted recipient.** Treat
it as a blast-radius reducer, not a guarantee.

**Why packet-filtering alone isn't enough.** nftables filters on IP/port, but the hosts we must
allow (Anthropic API, npm, PyPI, GitHub, …) sit behind shared, rotating CDN IP ranges — "allow
`github.com`" would in practice allow a whole CDN. Reliable allow-listing **by name** needs a
layer-7 chokepoint. So the planned design is layered:

- **nftables, default-deny** — drop all direct outbound from the VM;
- **a forced filtering proxy** (e.g. tinyproxy / Squid) as the only way out for HTTP/HTTPS — it
  allows a small list of **hostnames** (via SNI / `CONNECT`), not IPs: `api.anthropic.com`, the
  registries you use (npmjs, PyPI, Maven Central, crates.io …), `github.com` + your git remotes;
- **DNS forced** to a resolver restricted to those names — closes the DNS-tunnel exfil channel;
- **logging** of denied connections — a dependency suddenly dialing an unknown host is itself a
  tripwire.

It will ship as a step in [`scripts/vm-provision.sh`](scripts/vm-provision.sh) plus a small
`vm-firewall.sh` to view / edit / reload the hostname allowlist, with the rules + allowlist
version-controlled here so both Macs stay identical.

Defense in depth does the rest: the VM holds **no host secrets**, the OAuth token is injected per
session (never stored in the VM), and `~/Projects` — the only sensitive thing reachable — is already
in git and pushed, so residual exfil value ≈ source code that's already on GitHub.

<!-- TODO(firewall): once implemented, replace this stub with the actual nftables rules, the proxy
     config + hostname allowlist file, "how to allow a new host", and the DNS setup. Until then,
     VM egress is open. -->

## Start a new project the right way

```bash
# scaffold → open the editor → start the agent, in one line:
./05-new-project.sh my-app --redis && cd ../my-app && code . && claude
```

`code .` opens **VS Code on the project so you can watch and read the code while
Claude writes it** — they're the same files on disk, so edit in either. This is the
recommended setup: **editor (read) + Claude (write) side by side** on your main
screen (see [docs/workspace-and-monitoring.md](docs/workspace-and-monitoring.md)).
`--redis` is optional — it wires the Redis MCP for this project; omit it (or pass
`--no-mcp`) to skip. `make new-project NAME=my-app` also works.

It asks whether to add the **Redis MCP** to this project (or use `--redis` / `--no-mcp`).
Inside Claude, run `/brainstorm` to qualify the idea before any code. The
scaffold already includes a project `CLAUDE.md`, human `README.md`, the
`docs/` structure (PRD, specs, architecture, ADRs), `.gitignore`,
`.gitleaks.toml`, and CI workflows (tests, secret scan, dependency audit).

## Per-project `.claude/settings.json` recipes (by stack)

A project's `.claude/settings.json` **merges with your global** `~/.claude/settings.json`
(allow-lists are unioned). Use the per-project file for **stack-specific** bits so tests run
**sandboxed without prompts**:
- **`env`** — point package caches at a **sandbox-writable** path (project-local) + test flags;
- **`sandbox.network.allowedDomains`** — the package registries the sandbox may reach;
- a few **`Bash(...)`** allows for tools not already in your global list.

Gitignore the cache dirs. Tune the sandbox live with **`/sandbox`** (see
[sandboxing docs](https://code.claude.com/docs/en/sandboxing)).

**Python (uv + pytest)**
```json
{
  "env": { "UV_CACHE_DIR": ".uv-cache", "TESTCONTAINERS_RYUK_DISABLED": "true" },
  "sandbox": { "network": { "allowedDomains": ["pypi.org", "files.pythonhosted.org"] } },
  "permissions": { "allow": ["Bash(uv:*)", "Bash(pytest:*)", "Bash(ruff:*)", "Bash(mypy:*)"], "deny": [], "ask": [] }
}
```
`.gitignore`: `.uv-cache/`

**Node / React (npm or pnpm + Vite)**
```json
{
  "env": { "npm_config_cache": ".npm-cache" },
  "sandbox": { "network": { "allowedDomains": ["registry.npmjs.org"] } },
  "permissions": { "allow": ["Bash(npm:*)", "Bash(pnpm:*)", "Bash(npx:*)", "Bash(vite:*)", "Bash(node:*)"], "deny": [], "ask": [] }
}
```
`.gitignore`: `.npm-cache/`  (pnpm store: `pnpm config set store-dir .pnpm-store` + gitignore it)

**Angular (ng)**
```json
{
  "env": { "npm_config_cache": ".npm-cache" },
  "sandbox": { "network": { "allowedDomains": ["registry.npmjs.org"] } },
  "permissions": { "allow": ["Bash(ng:*)", "Bash(npm:*)", "Bash(npx:*)", "Bash(node:*)"], "deny": [], "ask": [] }
}
```

**Java / Spring (Maven or Gradle)**
```json
{
  "env": { "GRADLE_USER_HOME": ".gradle" },
  "sandbox": { "network": { "allowedDomains": ["repo.maven.apache.org", "repo1.maven.org", "plugins.gradle.org", "services.gradle.org"] } },
  "permissions": { "allow": ["Bash(./mvnw:*)", "Bash(mvn:*)", "Bash(./gradlew:*)", "Bash(gradle:*)", "Bash(java:*)"], "deny": [], "ask": [] }
}
```
Maven: point the local repo at a writable path — `mvn -Dmaven.repo.local=.m2 …` — and gitignore `.m2/` `.gradle/`.

> **Integration tests** using Docker / testcontainers **can't run in the OS sandbox** (they
> need the Docker socket + container networking) → run those unsandboxed, or in a VM/devcontainer.

## What's in here

| Path | What it is |
|------|------------|
| `01-setup.sh` / `02-doctor.sh` | host installer (idempotent) / read-only health check |
| `03-vm-up.sh` | start + provision the always-on Colima VM — the isolated default env (`make vm-up`) |
| `04-vm-auth.sh` | authenticate the VM: `claude setup-token` → host-only token file (`make vm-auth`) |
| `05-new-project.sh` | scaffold a new project from `project-template/` (also `make new-project`) |
| `ccvm` | enter the VM at a project + open VS Code (the default isolated workflow) |
| `sync-project.sh` | pull updated kit infra files into an existing project (also `make sync-project`) |
| `grafana-up.sh` / `grafana-down.sh` | start / stop the Grafana dashboards — drives the OTEL/Grafana stack **inside the Colima VM** from the host + opens the browser |
| `scripts/` | the individual, re-runnable setup steps |
| `claude-config/CLAUDE.md` | **global engineering standards** (loaded every session) |
| `claude-config/settings.json` | model, permission allowlist, hook wiring (**host** profile: sandboxed) |
| `claude-config/settings.vm.json` | **VM** overlay: sandbox off + max autonomy (merged over the base by `03-vm-up.sh`) |
| `claude-config/hooks/git-secret-guard.sh` | blocks `git commit`/`push` if gitleaks finds a secret |
| `claude-commands/` | `/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync` |
| `project-template/` | the template `05-new-project.sh` copies from |
| `docs/claude-code-setup.md` | the full guide (also the "Claude Code setup" doc tab) |
| `docs/cheatsheet.md` | one-page daily reference |
| `docs/workspace-and-monitoring.md` | usage/limit tracking, context, OTEL dashboards, worktrees & multi-monitor layout |
| `docs/tooling-setup.md` | what the dev-tools step installs/wires + manual finishing steps |
| `docs/security-roadmap.md` | parked hardening plan: egress firewall + token capture-resistance |
| `docs/isolation.md` | the always-on Colima VM workflow (isolated default env) |
| `docs/migration-from-augment.md` | two-phase Augment→Claude Code handover: prompt 1 dumps Augment's state, prompt 2 (in the VM) verifies & adapts it |

## Keeping current

```bash
git -C path/to/claude-code-dev-setup pull   # get the latest kit (config symlinks update automatically)
./01-setup.sh                                  # idempotent re-run: refreshes skills, MCP, global config
# Claude Code self-updates in the background
```

**Existing projects** don't auto-update (the scaffold is a one-time copy). Global config
(`~/.claude`) is covered by the pull above. To pull updated kit *infra* files (secret-scan
hook, editorconfig, secret-scan CI) into a project — dry-run, then apply:
```bash
./sync-project.sh ../my-app            # show what differs (or: make sync-project DIR=../my-app)
./sync-project.sh ../my-app --apply    # copy them in, then review & commit
```
It never touches your customized files (CLAUDE.md, README, docs/, .gitignore, language CI).

## Uninstall / revert

Config files are symlinks into this repo; remove them and restore from the
backup the installer made:

```bash
rm ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/hooks/git-secret-guard.sh
rm ~/.claude/commands/{brainstorm,spec,plan-feature,ship,doc-sync}.md
ls ~/.claude/backups/      # restore anything you want from here
```

## License

MIT — see [LICENSE](LICENSE).
