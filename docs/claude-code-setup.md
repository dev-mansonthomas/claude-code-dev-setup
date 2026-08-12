# Claude Code setup

> The "Claude Code setup" tab of the Mac OS Setup guide.
> Goal: take you from zero to building professional applications with Claude
> Code, fast — assuming you already know how to code but are **new to Claude
> Code** (coming from Augment / Codex).
>
> *To put this in the Google Doc:* add a new tab, then paste this Markdown
> (Docs keeps the headings/lists). Or keep reading it in the repo — it's the
> source of truth.

---

## 0. The 60-second version

```bash
# On the host (Apple Silicon Mac). Prereqs: Homebrew, and `gh auth login` done.
git clone https://github.com/dev-mansonthomas/claude-code-dev-setup.git ~/Projects/claude-code-dev-setup
cd ~/Projects/claude-code-dev-setup
./01-setup.sh          # host baseline: Claude Code CLI + skills + MCP + global config
./02-doctor.sh         # health check (should be green)
./03-vm-up.sh          # start + provision the always-on Colima VM (the real dev environment)
./04-vm-auth.sh        # one-time: authenticate the VM (host-side token)
```

Then, for a project:

```bash
./05-new-project.sh my-app          # NEW project: scaffold under ~/Projects + auto-launch ccvm
# …or EXISTING: cd ~/Projects && git clone <url> && ccvm <name>
# …or OPEN one already under ~/Projects:  ccvm <name>
```

`ccvm` opens VS Code on the host **and** a Claude session **inside the VM**.
Inside Claude: `/brainstorm → /spec → /plan-feature → build → /code-review → /ship`.
When Claude has committed a branch, land it **from the host**: `git-pr-merge --branch <branch> "<title>"`.

Everything below explains *why* each piece exists and how to use it well.

---

## 1. Mental model — two shifts from Augment / Codex

### 1a. You steer the context (not a big auto-index)
Claude Code is a **terminal-first coding agent**. The biggest adjustment from
Augment is that **you manage context explicitly** — it's a feature, not a
limitation.

| Topic | Augment (what you're used to) | Claude Code (how it works) |
|---|---|---|
| **Context** | Large, auto-managed index | A finite context **you steer**: `CLAUDE.md` + files you `@`-mention + what the agent reads. Check with `/context`. |
| **Persistent memory** | Implicit in the index | **Explicit files**: `CLAUDE.md` (project + global) and `docs/`. The chat is scratch. |
| **Long sessions** | Handled for you | `/compact` to summarize, `/clear` to reset between tasks. |
| **Planning** | Intent plans | **Plan mode** (read-only): the agent explores and proposes a plan you approve before it edits. |
| **Extending** | MCP servers in the IDE | **Skills** + **MCP servers** + **slash commands** + **subagents** + **hooks**. |
| **Automation/guardrails** | UI settings | **Hooks** in `settings.json` run deterministically (e.g. the secret-scan guard). |

**The habit to build:** treat `CLAUDE.md` and `docs/` as the project's brain. If
something matters beyond this session, it goes in a file — not just the chat.

### 1b. Work runs in an isolated VM (this kit's core idea)
Real work runs inside an **always-on Colima Linux VM** — the security boundary.

- **You edit on the host** (VS Code), **Claude runs in the VM**. `~/Projects` is
  mounted into the VM at the same path, so the host sees Claude's commits instantly.
- The VM holds **no outward credentials** (no GitHub / cloud auth). So: **build &
  test in the VM; do every credentialed action — `git push`, PR, deploy — from the
  host.** A compromised dependency in the VM can't reach your GitHub or cloud.
- `ccvm <project>` is the one command that ties it together (VS Code + Claude-in-VM).

See [isolation.md](isolation.md) for the full model.

---

## 2. One-time setup (zero assumed knowledge)

**Prerequisites:** macOS on Apple Silicon, [Homebrew](https://brew.sh), and `gh`
authenticated (`gh auth login`).

```bash
git clone https://github.com/dev-mansonthomas/claude-code-dev-setup.git ~/Projects/claude-code-dev-setup
cd ~/Projects/claude-code-dev-setup
./01-setup.sh      # host baseline (idempotent). Flags: --copy, --no-mcp, --with-extras
./02-doctor.sh     # verify: CLI, skills, MCP, global config all green
./03-vm-up.sh      # bring up + provision the VM (installs the full toolchain inside it)
./04-vm-auth.sh    # one-time: `claude setup-token` on the host, stored for ccvm to inject
```

- **`01-setup.sh`** (host): installs the Claude Code CLI, the curated Skills, the
  user-scope MCP servers, and links the global `CLAUDE.md` + `settings.json` + the
  secret-guard hook + the workflow slash commands into `~/.claude`. Host
  monitoring/multi-project extras are **off by default** (they live in the VM);
  add them with `--with-extras`.
- **`03-vm-up.sh`** (VM): starts Colima and installs the whole dev toolchain
  *inside* the VM (see §4.6), plus the skills/MCP/plugins and monitoring.
- **`04-vm-auth.sh`**: opens a browser on the host for `claude setup-token`, stores
  the long-lived token host-side (chmod 600); `ccvm` injects it per-session — it's
  never written into the VM or under `~/Projects`, so it can't be committed.

**Multi-line prompts in `ccvm`** (one-time host terminal tweak — `ccvm` runs Claude
over SSH, so `/terminal-setup` can't run there):
- Any terminal: press **`Ctrl+J`** for a newline (Enter submits).
- iTerm2: *Settings → Profiles → Keys → Key Mappings → `+` → Shift+Return → Send
  Hex Codes → `0x0a`* (gives you Shift+Enter).

**Keep a second Mac in sync:** `git pull` in the kit repo, then `./03-vm-up.sh`.

---

## 3. The professional loop

The workflow your global `CLAUDE.md` enforces — one slash command per step,
applied to every project:

- **`/brainstorm`** — qualify a fuzzy idea into a one-page brief *before any code*.
- **`/spec`** — turn the brief into an agent-facing spec (`docs/specs/<feature>.md`):
  inputs, outputs, edge cases, acceptance criteria.
- **`/plan-feature`** — break the spec into a small, **test-first (TDD)** plan.
- **Implement** — the smallest change that makes the failing test pass; match the
  surrounding style.
- **`/code-review`** then **`/security-review`** — correctness first, then anything
  touching auth / input / data (**`/verify`** runs the app to confirm behavior).
- **`/ship`** — pre-push gate: tests + lint + typecheck + build + dependency audit +
  **secret scan** + docs check.
- **Deploy** — Claude generates an idempotent `deploy/gcp-deploy.sh` that **you
  review and run on the host** (never from the VM).
- **`/doc-sync`** — keep the human `README` and the agent docs in step with the code.

Two cross-cutting rules baked into the global `CLAUDE.md`:
- **Latest versions**: before adding/upgrading a library, the agent confirms the
  current stable version + API via the **Context7 MCP** (say *"use context7"*),
  not training memory.
- **Never "done" without proof**: it runs the tests/build and shows the real output.

**Plan mode** for anything non-trivial (press **Shift+Tab** to cycle to it): the
agent explores read-only and proposes a plan you approve before edits. Escalate
reasoning with **"think" / "think hard" / "ultrathink"** on genuinely hard problems.

---

## 4. Working day-to-day

### 4.1 Open or create a project
Everything lives under **`~/Projects`** (the only folder mounted in the VM).

| Case | Command |
|---|---|
| **New** project (full scaffold + auto-launch ccvm) | `./05-new-project.sh my-app` |
| **Existing** GitHub project | `cd ~/Projects && git clone <url> && ccvm <name>` |
| **Open** one already under `~/Projects` | `ccvm <name>` |

`ccvm <name>` opens VS Code on the host and a Claude session inside the VM at that
project. It does **not** create anything — the directory must already exist.
`ccvm` alone just shells into the VM.

### 4.2 Autonomy — `auto` permission mode
`ccvm` launches Claude with **`--permission-mode auto`**: it auto-runs commands and
auto-applies edits, gated by a safety classifier that blocks destructive/outward
ops. This is the autonomous mode that works on managed (Redis Enterprise) accounts —
`bypassPermissions` is disabled by org policy there. Escape hatches: `CCVM_SAFE=1`
→ `acceptEdits` (edits only), `CCVM_YOLO=1` → request bypass (only where allowed).

> Subagents in auto mode are covered by the same classifier, but the classifier is
> conservative about **infrastructure edits** (Terraform, etc.). The kit tells it
> the VM is a credential-free box so routine IaC edits aren't prompted.

### 4.3 Ship from the host (the VM has no credentials)
When Claude has committed a branch in the VM, land it **from the host** with the
kit's helpers (on your `PATH`):

```bash
git-pr-merge --branch <branch> "<title>" "<body>"   # push → open/reuse PR → wait for CI → squash-merge → sync main → prune
git-check                                            # read-only snapshot of open PRs, merges, remote branches
```
Both write a JSON report to `debug/git/` that the VM's Claude can read back to
confirm the merge or handle a CI failure. **Deploy** is host-side too: review and
run `./deploy/gcp-deploy.sh`.

### 4.4 See the UI Claude built
Screenshot a page reliably from the VM (verify a UI):
```bash
npx playwright screenshot --browser=chromium --full-page http://localhost:<port> /tmp/ui.png
```
…or the Playwright MCP (`browser_navigate` → `browser_take_screenshot`). Don't fight
raw `chromium --headless --screenshot` (finicky; prints a harmless DBus error).

---

## 5. Your toolbox

### 5.1 Skills — expertise Claude loads itself
Skills **auto-trigger from their `description`** — Claude invokes the matching one
itself (you *can* name one: "use the redis-vector-search skill"). Installed in the VM:

- **Redis engineering** (`redis/agent-skills`): `redis-core`, `redis-clustering`,
  `redis-connections`, `redis-query-engine`, `redis-vector-search`,
  `redis-semantic-cache`, `redis-observability`, `redis-security`.
- **Redis SA toolkit** (`fcenedes/redis_sa_skills`): `redis-brand-ui`,
  `redis-product-ui`, `redis-presentation-decks`, `redis-excalidraw-diagrams`,
  `redis-lucidchart-diagrams`, `redis-insight-plugin`, `playwright-test`,
  `playwright-cli-agent`, `caveman`, `rtk-cli`, the `agent-*` coordination set.
- **Anthropic** (`anthropics/skills`): `frontend-design`, `web-artifacts-builder`,
  `canvas-design`, `theme-factory`, `mcp-builder`, `webapp-testing`, `pdf`, `docx`,
  `pptx`, `xlsx`, `skill-creator`.
- **Vercel** (`vercel-labs`): `react-best-practices`, `web-design-guidelines`;
  `find-skills` (skill discovery).
- **Code/file search**: `file-search` (ripgrep + ast-grep + `fd`).

Manage: `ls ~/.claude/skills` · re-run `./03-vm-up.sh` to refresh from the kit.

### 5.2 MCP servers
User scope (`claude mcp list`):
- **Context7** — up-to-date, version-specific library docs. Trigger: *"use context7"*.
- **Playwright** (`--browser chromium`) — drive a real browser; UI build/validation.
- **Sequential-Thinking** — structured multi-step reasoning.
- **redis-docs** — the official Redis documentation (`https://redis.io/mcp`).
- **obscura** *(VM-only)* — a stealth headless browser; **fallback** for web research
  when a site blocks/filters/CAPTCHAs you or needs JS rendering. Not the default —
  respect robots.txt / rate limits / site ToS.

**Redis *data* MCP is per-project** (needs a DB + connection string). Add it inside
a project so the agent can query your data:
```bash
claude mcp add --scope project redis -- \
  uvx --from redis-mcp-server@latest redis-mcp-server \
  --url redis://<user>:<password>@127.0.0.1:6399/0
```
`./05-new-project.sh <name> --redis` writes this `.mcp.json` for you.

### 5.3 Plugin — methodology
**`superpowers`** (official `claude-plugins-official` marketplace) adds
planning/TDD/debugging skills **and** instructions that make Claude actively use
them — run `/using-superpowers` in a session.

### 5.4 Slash commands
Built-in: `/context` `/compact` `/clear` `/init` `/agents` `/mcp` `/plugin`
`/code-review` `/security-review` `/verify` `/model` `/status` `/resume`.
Kit workflow commands: **`/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync`**.

### 5.5 Subagents & hooks
- **Subagents** (`/agents`) — scoped helpers with their own context; delegate broad
  searches or independent chunks so the main context stays clean.
- **Hooks** — the kit ships **`git-secret-guard.sh`** (`PreToolUse` on Bash): scans
  staged content with gitleaks before `git commit`/`push` and **blocks** on a
  secret; fails open (warns) if gitleaks is missing.

### 5.6 VM toolchain (pre-installed — use it, don't reinstall)
Node 24, JDK 21 + Maven, **Go**, **Rust** (rustup), **.NET SDK** (LTS), `redis-cli`
8, `luacheck`, **OpenTofu** (`tofu` — validate-only: `fmt -check` / `validate`;
`plan/apply` stay host-side), Playwright browsers (chromium/firefox/webkit), plus
`fd`, `uv`, `gh`, `jq`, `shellcheck`, and network/debug tools (dig, tcpdump/tshark,
nmap, httpie, grpcurl, strace, htop…). Missing something? Add it to
`scripts/vm-provision.sh`, then `./03-vm-up.sh`.

---

## 6. Security & git hygiene (code + what's pushed)

Defense in depth:

- **VM isolation** — the VM has no GitHub/cloud credentials, so a compromised
  dependency can't exfiltrate them; push/PR/deploy happen host-side.
- **Per-project pre-commit hook** (gitleaks on the staged snapshot) + a **global
  secret-guard** backstop in `~/.claude`. Teammates run `git config core.hooksPath
  .githooks` once after cloning.
- **Server-side** (can't be skipped with `--no-verify`): `secret-scan.yml` on every
  push/PR, plus GitHub **Push Protection + Secret scanning** (enable in repo
  Settings). `dependency-audit.yml` + `ci-node.yml` round it out.
- **Code security** from the loop: `/security-review` on anything touching
  auth/input/data; the `redis-security` skill for ACLs/TLS/exposure; OWASP by default.

> If gitleaks flags a false positive, add an allow rule to `.gitleaks.toml` — don't
> disable the scan.

---

## 7. Performance & Redis practices

- Ask the agent to **name the cost** before optimizing: hot paths, N+1, unbounded
  memory, blocking I/O, missing indexes.
- For Redis, the `redis-*` skills encode the defaults: **never `KEYS` in production**
  (use `SCAN`), right data structure, pool/multiplex connections, watch `CROSSSLOT`
  in clusters, pipeline bulk ops, read from replicas for read-heavy loads.
- Diagnose with `redis-observability`: `SLOWLOG`, `INFO`, `MEMORY DOCTOR`,
  `FT.PROFILE`, Redis Insight. Your `redis-cluster-audit` tool audits real clusters.

---

## 8. Documentation — two audiences, always

Every scaffolded project separates them:
- **Humans → `README.md`**: step-by-step, **zero assumed knowledge** — prerequisites,
  exact copy-paste commands, "success looks like…", troubleshooting.
- **Agents → `docs/`**: `product/PRD.md` (problem/users/scope), `specs/*.md`
  (per-feature contracts), `architecture/overview.md`, `adr/*.md` (decisions + *why*),
  and the project `CLAUDE.md` (entry map).

Run `/doc-sync` to reconcile docs with code — in the same change that alters behavior.

---

## 9. Tutorial — build your first app end-to-end (≈30–45 min)

A small but real **Redis-backed URL shortener**. It exercises the whole loop.

```bash
./05-new-project.sh shortlink     # scaffolds ~/Projects/shortlink + launches ccvm
```

Inside the ccvm Claude session:
1. **`/brainstorm`** *"a URL shortener: paste a long URL, get a short code, visiting it redirects"* — answer its questions; it writes `docs/product/brief.md`. Keep scope tiny.
2. **`/spec create-and-redirect`** — review the acceptance criteria are testable (e.g. *POST a valid URL → 7-char code*; *GET /:code → 302*; *invalid URL → 400*).
3. **`/plan-feature create-and-redirect`** — it checks library versions via Context7, then writes **failing tests first**.
4. **Implement** — minimal code to pass each test. Watch the Redis model (`redis-core` skill: a key like `shortlink:<code>`, maybe a TTL); push back if it reaches for `KEYS`. Run Redis in the VM: `docker run -d -p 6379:6379 redis:latest`.
5. *"add a Playwright test that creates a link in the UI and follows the redirect"* — uses `playwright-test` + the Playwright MCP.
6. **`/code-review`** then **`/security-review`** — confirm input validation, no open redirect, no secrets.
7. **`/ship`** — the full gate; try committing a fake secret once to watch the guard block it. 🙂
8. **`/doc-sync`** — make the `README` truly copy-paste runnable.
9. **On the host:** `git-pr-merge --branch <branch> "feat: create-and-redirect"` → PR → CI → merged on `main`.

You've now run the full professional loop on a real app, VM-isolated end to end.

---

## 10. Daily cheat sheet

**Host**
```bash
ccvm <project>                 # VS Code (host) + Claude (VM)
ccvm                           # shell into the VM
./02-doctor.sh                 # health check
git-pr-merge --branch <b> "…"  # push → PR → CI → squash-merge
git-check                      # read-only GitHub/remote state
git pull && ./03-vm-up.sh      # refresh the VM after a kit update
```

**In-session**
| Want to… | Do |
|---|---|
| Plan before editing | Shift+Tab → plan mode |
| See / free context | `/context` · `/compact` (same task) · `/clear` (new task) |
| Pin a file / save a fact | `@path/to/file` · start a line with `#` |
| Think harder | add "think hard" / "ultrathink" |
| Review code / security / behavior | `/code-review` · `/security-review` · `/verify` |
| Run the workflow | `/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync` |
| See MCP / skills | `/mcp` · `ls ~/.claude/skills` |
| Screenshot a UI | `npx playwright screenshot --browser=chromium <url> out.png` |
| Track usage / limit | `claude-monitor` (in the VM) · `npx ccusage@latest blocks --live` |

**Troubleshooting**
| Symptom | Fix |
|---|---|
| `ccvm: Colima not running` | `./03-vm-up.sh` (or `colima start`) |
| `ccvm <name>`: "Project not found" | it must exist under `~/Projects` — scaffold with `05-new-project.sh` or clone it first |
| MCP not responding | restart the ccvm session (MCP loads at session start); `/mcp` to re-auth |
| A model missing from `/model` | it's account/entitlement-based, not a bug |
| Hook blocks a legit commit | it found a secret-shaped string — fix it, or allowlist in `.gitleaks.toml` |
| Skill not triggering | name it explicitly; `ls ~/.claude/skills` to confirm it's installed |

---

### Reference
- This kit: `claude-code-dev-setup` — `./02-doctor.sh` anytime; [isolation.md](isolation.md), [workspace-and-monitoring.md](workspace-and-monitoring.md).
- Redis skills: `redis/agent-skills`, `fcenedes/redis_sa_skills`.
- Claude Code docs: <https://code.claude.com/docs>.
