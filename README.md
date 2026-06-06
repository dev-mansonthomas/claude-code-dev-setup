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
| A Claude Pro/Max/Team/Enterprise/Console account | — | required for Claude Code |

The script installs `gh`, `gitleaks`, `uv`, and `jq` via Homebrew if missing.

## Quickstart

```bash
# 1. get this repo
git clone https://github.com/dev-mansonthomas/claude-code-dev-setup.git
cd claude-code-dev-setup

# 2. install & configure everything (idempotent — safe to re-run)
./setup.sh

# 3. open a NEW terminal so `claude` is on your PATH, then verify
./doctor.sh
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
   wired into `settings.json`. See [docs/tooling-setup.md](docs/tooling-setup.md).

### Options

```bash
./setup.sh --copy        # copy config into ~/.claude instead of symlinking
./setup.sh --no-mcp      # skip MCP registration
./setup.sh --no-extras   # skip the monitoring/multi-project tooling
./setup.sh --yes         # non-interactive (assume yes)
```

By default config is **symlinked** from this repo into `~/.claude`, so
`git pull` here keeps both your MacBooks in sync.

## Start a new project the right way

```bash
make new-project NAME=my-app
cd ../my-app
claude
```

Inside Claude, run `/brainstorm` to qualify the idea before any code. The
scaffold already includes a project `CLAUDE.md`, human `README.md`, the
`docs/` structure (PRD, specs, architecture, ADRs), `.gitignore`,
`.gitleaks.toml`, and CI workflows (tests, secret scan, dependency audit).

## What's in here

| Path | What it is |
|------|------------|
| `setup.sh` / `doctor.sh` | installer (idempotent) / read-only health check |
| `scripts/` | the individual, re-runnable setup steps |
| `claude-config/CLAUDE.md` | **global engineering standards** (loaded every session) |
| `claude-config/settings.json` | model, permission allowlist, hook wiring |
| `claude-config/hooks/git-secret-guard.sh` | blocks `git commit`/`push` if gitleaks finds a secret |
| `claude-commands/` | `/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync` |
| `project-template/` | scaffold copied by `make new-project` |
| `docs/claude-code-setup.md` | the full guide (also the "Claude Code setup" doc tab) |
| `docs/cheatsheet.md` | one-page daily reference |
| `docs/workspace-and-monitoring.md` | usage/limit tracking, context, OTEL dashboards, worktrees & multi-monitor layout |
| `docs/tooling-setup.md` | what the dev-tools step installs/wires + manual finishing steps |

## Keeping current

```bash
git -C path/to/claude-code-dev-setup pull   # update config (symlinks pick it up)
npx skills update                            # refresh installed skills
# Claude Code self-updates in the background
```

## Uninstall / revert

Config files are symlinks into this repo; remove them and restore from the
backup the installer made:

```bash
rm ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/hooks/git-secret-guard.sh
ls ~/.claude/backups/      # restore anything you want from here
```

## License

MIT — see [LICENSE](LICENSE).
