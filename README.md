# claude-code-dev-setup

Reproducible, professional **Claude Code** setup for building real applications —
tuned for a Redis Solution Architect's workflow: qualify the need → spec →
test-first → performance & security aware → ship with clean git → document for
both humans and agents.

Run one command on a fresh Mac (or your second MacBook) and get the same
Claude Code environment: the CLI, the right Skills, useful MCP servers, a strong
global `CLAUDE.md`, a secret-scanning git guard, workflow slash commands, and a
project scaffolder.

> New to all this? Read **[docs/claude-code-setup.md](docs/claude-code-setup.md)** —
> a zero-assumed-knowledge guide that takes you from install to top-level.

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
./setup.sh

# 3. open a NEW terminal so `claude` is on your PATH
exec zsh -l                      # (or just open a new tab/window)

# 4. log in to Claude Code (first run only), then verify
claude                           # complete the one-time login, then quit
./doctor.sh                      # expect mostly green: CLI, linked config, skills, MCP, dev tooling
```

That's it. `setup.sh` will:

1. **Preflight** — check macOS/brew/git/node, install `gh` `gitleaks` `uv` `jq`.
2. **Claude Code** — install the CLI via the official native installer.
3. **Skills** — install the Redis SA + official Redis + frontend-design skills.
4. **MCP servers** — add Context7, Playwright, Sequential-Thinking (user scope).
5. **Plugins** — show how to add marketplaces (interactive, optional).
6. **Global config** — link `CLAUDE.md`, `settings.json`, the secret-guard hook,
   and the workflow slash commands into `~/.claude` (your existing files are
   backed up first).
7. **Dev tooling** — install the usage gauge (`claude-monitor`), Claude Squad (`cs`),
   and clone the OTEL/Grafana stack; the status line (ccstatusline) and telemetry are
   wired into `settings.json`. Start the dashboards anytime with **`./grafana-up.sh`**
   (needs Docker running; stop: `./grafana-down.sh`). See [docs/tooling-setup.md](docs/tooling-setup.md).

### Options

```bash
./setup.sh --copy        # copy config into ~/.claude instead of symlinking
./setup.sh --no-mcp      # skip MCP registration
./setup.sh --no-plugins  # skip the (optional) plugins info step
./setup.sh --no-extras   # skip the monitoring/multi-project tooling
./setup.sh --interactive # confirm before each step (default: non-interactive)
```

By default config is **symlinked** from this repo into `~/.claude`, so
`git pull` here keeps both your MacBooks in sync.

## Run everything in an isolated VM (recommended)

For strong isolation, run Claude + tools + Docker inside an **always-on Colima Linux VM**.
You edit on the host (`~/Projects` is mounted in); Claude, builds, tests and the Grafana
stack run **in the VM** — a compromised dep/agent can't touch `~/.ssh`, your keychain, or the
rest of macOS.
```bash
./vm-up.sh                 # once: start + provision the VM  (make vm-up)
cc my-app                  # open VS Code on the host + a Claude session inside the VM
```
`new-project.sh` auto-launches `cc` after scaffolding; monitoring (Grafana) runs in the same
VM (no second VM). Inside the VM you can safely use `--dangerously-skip-permissions`.
Full guide + caveats: **[docs/isolation.md](docs/isolation.md)**.

## Start a new project the right way

```bash
# scaffold → open the editor → start the agent, in one line:
./new-project.sh my-app --redis && cd ../my-app && code . && claude
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
| `setup.sh` / `doctor.sh` | installer (idempotent) / read-only health check |
| `grafana-up.sh` / `grafana-down.sh` | start / stop the local Grafana monitoring dashboards |
| `new-project.sh` | scaffold a new project from `project-template/` (also `make new-project`) |
| `sync-project.sh` | pull updated kit infra files into an existing project (also `make sync-project`) |
| `vm-up.sh` | start + provision the always-on Colima VM — the isolated default env (`make vm-up`) |
| `cc` | enter the VM at a project + open VS Code (the default isolated workflow) |
| `scripts/` | the individual, re-runnable setup steps |
| `claude-config/CLAUDE.md` | **global engineering standards** (loaded every session) |
| `claude-config/settings.json` | model, permission allowlist, hook wiring |
| `claude-config/hooks/git-secret-guard.sh` | blocks `git commit`/`push` if gitleaks finds a secret |
| `claude-commands/` | `/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync` |
| `project-template/` | the template `new-project.sh` copies from |
| `docs/claude-code-setup.md` | the full guide (also the "Claude Code setup" doc tab) |
| `docs/cheatsheet.md` | one-page daily reference |
| `docs/workspace-and-monitoring.md` | usage/limit tracking, context, OTEL dashboards, worktrees & multi-monitor layout |
| `docs/tooling-setup.md` | what the dev-tools step installs/wires + manual finishing steps |
| `docs/isolation.md` | the always-on Colima VM workflow (isolated default env) |

## Keeping current

```bash
git -C path/to/claude-code-dev-setup pull   # get the latest kit (config symlinks update automatically)
./setup.sh                                  # idempotent re-run: refreshes skills, MCP, dev tools, config
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
