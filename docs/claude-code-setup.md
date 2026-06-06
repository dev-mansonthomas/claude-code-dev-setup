# Claude Code setup

> The "Claude Code setup" tab of the Mac OS Setup guide.
> Goal: take you from zero to building professional applications with Claude
> Code, fast — assuming you already know how to code but are **new to Claude
> Code** (coming from Augment / Codex).
>
> *To put this in the Google Doc:* add a new tab, then paste this Markdown
> (Docs keeps the headings/lists). Or keep reading it in the repo — it's the
> source of truth. (I can also push it to your Drive via the Drive MCP on
> request.)

---

## 0. The 60-second version

```bash
git clone https://github.com/dev-mansonthomas/claude-code-dev-setup.git
cd claude-code-dev-setup && ./setup.sh
# open a new terminal, then:
./doctor.sh
```

Then, for every new app:

```bash
./new-project.sh my-app && cd ../my-app && claude
# inside Claude:  /brainstorm  →  /spec  →  /plan-feature  →  build  →  /ship
```

Everything below explains *why* each piece exists and how to use it well.

---

## 1. Mental model — what changes coming from Augment / Codex

Claude Code is a **terminal-first coding agent**. The biggest adjustment from
Augment is that **you manage context explicitly** — it's a feature, not a
limitation. Once you internalize that, you'll trust the agent more because you
always know what it's looking at.

| Topic | Augment (what you're used to) | Claude Code (how it works) |
|---|---|---|
| **Context** | Large, auto-managed index of your repo | A finite context **you steer**: `CLAUDE.md` + files you `@`-mention + what the agent reads. Check it with `/context`. |
| **Persistent memory** | Implicit in the index | **Explicit files**: `CLAUDE.md` (project + global) and `docs/`. The chat is scratch. |
| **Long sessions** | Handled for you | `/compact` to summarize, `/clear` to reset between tasks. |
| **Planning** | Intent plans | **Plan mode** (read-only): the agent explores and proposes a plan you approve before it touches code. |
| **Extending** | MCP servers in the IDE | **Skills** (auto-loaded expertise) + **MCP servers** + **slash commands** + **subagents** + **hooks**. |
| **Where it runs** | VS Code extension | CLI in iTerm2 (also IDE extensions, desktop, web). This guide is CLI-first. |
| **Automation/guardrails** | UI settings | **Hooks** in `settings.json` (e.g. our secret-scan guard) run deterministically. |

**The one habit to build:** treat `CLAUDE.md` and `docs/` as the project's
brain. If something matters beyond this session, it goes in a file — not just
the chat.

---

## 2. One-time setup (zero assumed knowledge)

### 2.1 Install
The `setup.sh` in this repo does it all and is safe to re-run. It:

1. **Preflight** — verifies Homebrew, git, Node, Python; installs `gh`,
   `gitleaks`, `uv`, `jq`.
2. **Claude Code CLI** — `curl -fsSL https://claude.ai/install.sh | bash`
   (native installer, no Node dependency, auto-updates).
3. **Skills** — installs the skill collections (see §4.1).
4. **MCP servers** — Context7, Playwright, Sequential-Thinking (user scope).
5. **Global config** — links `CLAUDE.md`, `settings.json`, the secret-guard
   hook, and the slash commands into `~/.claude` (backing up anything existing).

```bash
./setup.sh            # full
./setup.sh --copy     # copy instead of symlink
./setup.sh --no-mcp   # skip MCP
```

### 2.2 First launch & login
```bash
claude            # in any project directory
```
On first run it walks you through login (use your Claude Pro/Max or Console
account). Then:

- `/status` — see account, model, and config.
- `/model` — pick the model (default here is **Opus**; toggle Fast mode with
  `/fast`).
- `/doctor` (Claude's own) and our `./doctor.sh` — confirm everything's wired.

### 2.3 Verify
```bash
./doctor.sh
```
Green across the board means: CLI installed, skills present, MCP servers
configured, global `CLAUDE.md` + `settings.json` + hook in place.

---

## 3. The professional loop

This is the workflow your global `CLAUDE.md` enforces. It maps 1:1 to your
requirements (brainstorm, tests, performance, security, latest versions, docs).

```
qualify → spec → plan(TDD) → implement → review → ship → document
   │        │       │            │          │       │        │
/brainstorm /spec /plan-feature  code   /code-review /ship  /doc-sync
                                        /security-review
```

| Step | Command | What it produces | Your requirement |
|---|---|---|---|
| **Qualify** | `/brainstorm` | `docs/product/brief.md` | "brainstorm to define & qualify the need" |
| **Spec** | `/spec <feature>` | `docs/specs/<feature>.md` (agent-facing) | clear specs per feature |
| **Plan (TDD)** | `/plan-feature <feature>` | ordered red→green→refactor task list | unit tests first |
| **Implement** | (just build) | code + passing tests | — |
| **Review** | `/code-review`, `/security-review` | findings to fix | performance & security of code |
| **Ship** | `/ship` | tests+lint+types+build+audit+**secret scan**+docs gate | security of what's committed/pushed |
| **Document** | `/doc-sync` | updated human + agent docs | dual-audience docs |

Two cross-cutting rules baked into the global `CLAUDE.md`:

- **Latest versions**: before adding/upgrading a library, the agent confirms the
  current stable version and API via the **Context7 MCP** (say *"use context7"*)
  instead of trusting training memory.
- **Never "done" without proof**: the agent runs the tests/build and shows you
  the real output.

### Use plan mode for anything non-trivial
Press **Shift+Tab** to cycle input modes until you see **plan mode**. The agent
explores read-only and proposes a plan; you approve before any edits. This is
the Claude-Code equivalent of an Augment Intent plan — use it liberally for
multi-file work.

### Escalate thinking when it's hard
Add **"think"**, **"think hard"**, or **"ultrathink"** to a prompt to give the
model more reasoning budget on genuinely tricky problems (architecture, gnarly
bugs). Don't use it for routine edits.

---

## 4. Your toolbox

### 4.1 Skills — expertise that auto-loads
Skills are instruction sets the agent pulls in **automatically** when relevant
(based on their description), or you can nudge it ("use the redis-vector-search
skill"). You already have ~29 installed. The ones you'll lean on:

- **Redis engineering** (`redis/agent-skills`): `redis-core`, `redis-clustering`,
  `redis-connections`, `redis-query-engine`, `redis-vector-search`,
  `redis-semantic-cache`, `redis-observability`, `redis-security`.
- **Redis SA toolkit** (`fcenedes/redis_sa_skills`): `redis-brand-ui`,
  `redis-product-ui`, `redis-presentation-decks`, `redis-excalidraw-diagrams`,
  `redis-lucidchart-diagrams`, `redis-insight-plugin`, `playwright-test`,
  `playwright-cli-agent`, `caveman`, `rtk-cli`, the `agent-*` coordination set.
- **Frontend** (`anthropics/skills`): `frontend-design`; plus
  `web-design-guidelines` for a11y/UX review.

Manage them:
```bash
npx skills list          # what's installed
npx skills update        # refresh
npx skills add owner/repo --skill name -g -a claude-code
```

### 4.2 MCP servers — connect external capabilities
Configured at **user scope** by setup (`claude mcp list` to see them):

- **Context7** — up-to-date, version-specific docs for any library. Kills
  hallucinated/outdated APIs. Trigger: *"use context7"*.
- **Playwright** — drive a real browser (navigate, click, screenshot) for
  building/validating web UIs.
- **Sequential-Thinking** — structured multi-step reasoning for complex tasks.

**Redis MCP is per-project** (it needs a DB + connection string, like you set up
in Augment). Add it inside a project so the agent can query your data directly:

```bash
claude mcp add --scope project redis -- \
  uvx --from redis-mcp-server@latest redis-mcp-server \
  --url redis://<user>:<password>@127.0.0.1:6399/0
```
This writes `.mcp.json` in the project. Keep the password in an env var; commit
`.mcp.json` only if it contains no secret.

### 4.3 Slash commands
Built-in essentials:

| Command | Use |
|---|---|
| `/context` | see what's filling the context window |
| `/compact` | summarize the session to free context (mid-task) |
| `/clear` | wipe context between unrelated tasks |
| `/init` | generate a starter `CLAUDE.md` for a repo |
| `/agents` | create/manage subagents |
| `/mcp` | view/authenticate MCP servers |
| `/plugin` | browse & install plugins/marketplaces |
| `/code-review`, `/security-review` | built-in review passes |
| `/resume`, `claude -c` | resume a previous session |
| `/vim`, `/config`, `/model`, `/status` | editor mode, settings, model, status |

Your custom workflow commands (installed by this kit): **`/brainstorm`**,
**`/spec`**, **`/plan-feature`**, **`/ship`**, **`/doc-sync`**.

### 4.4 Subagents — parallelism without polluting context
Subagents are scoped helpers (their own context window) you delegate to —
ideal for broad searches or independent chunks so the **main** context stays
clean. Manage with `/agents`. Use them when a task says "search the whole repo
for X" or when you can split work into independent parts.

### 4.5 Hooks — deterministic guardrails
Hooks are commands the harness runs on events (defined in `settings.json`). This
kit ships one: **`git-secret-guard.sh`** (a `PreToolUse` hook on Bash). Before
the agent runs `git commit`/`git push`, it scans staged content with gitleaks
and **blocks** if it finds a secret. It fails open (warns) if gitleaks is
missing, so it never bricks your git.

### 4.6 Plan mode, memory shortcuts, files
- **`@path/to/file`** in a prompt pins that file into context.
- **Start a line with `#`** to quickly save a fact to memory (`CLAUDE.md`).
- **Drag an image** into the terminal (or paste) to discuss a screenshot/mockup.
- **`claude -p "…"`** runs headless (great for scripts/CI).

---

## 5. Security & git hygiene (code + what's pushed)

Two layers, because you asked for both:

**Local (fast feedback)**
- The **secret-guard hook** stops secrets at commit/push time.
- The global `CLAUDE.md` requires: env vars for all secrets, `.gitignore`
  covering `.env*`/keys, review the diff before committing, Conventional
  Commits, branch off `main`, **push only when you ask**.

**CI (enforced for the team)** — in every scaffolded project:
- `secret-scan.yml` — gitleaks on every push/PR.
- `dependency-audit.yml` — `npm audit` (High/Critical) on PRs + weekly.
- `ci-node.yml` — lint, typecheck, test, build.

**Code security** comes from the loop: `/security-review` on anything touching
auth, input, or data; the `redis-security` skill for ACLs/TLS/exposure; OWASP
basics by default for web.

> Tip: if gitleaks flags a false positive, add an allow rule to the project's
> `.gitleaks.toml` rather than disabling the scan.

---

## 6. Performance & Redis practices

- Ask the agent to **name the cost** before optimizing: hot paths, N+1,
  unbounded memory, blocking I/O, missing indexes.
- For Redis, the `redis-*` skills encode the right defaults: **never `KEYS` in
  production** (use `SCAN`), pick the right data structure, pool/multiplex
  connections, watch `CROSSSLOT` in clusters, pipeline bulk ops, read from
  replicas for read-heavy loads.
- Use `redis-observability` when diagnosing: `SLOWLOG`, `INFO`, `MEMORY DOCTOR`,
  `FT.PROFILE`, and Redis Insight.
- Your `redis-cluster-audit` tool is a good companion for auditing real clusters.

---

## 7. Documentation — two audiences, always

Every scaffolded project separates them:

- **Humans → `README.md`**: step-by-step, **zero assumed knowledge**.
  Prerequisites table, exact copy-paste commands to install/run/test, "success
  looks like…", troubleshooting. A first-timer must succeed without asking you.
- **Agents → `docs/`**:
  - `product/PRD.md` — problem, users, scope.
  - `specs/*.md` — per-feature contracts (inputs/outputs/edge cases/tests).
  - `architecture/overview.md` — components, data flow, Redis keys/types.
  - `adr/*.md` — decisions + *why* (so agents don't re-derive or contradict).
  - project `CLAUDE.md` — the entry map.

Run `/doc-sync` to reconcile docs with code; update docs **in the same change**
that alters behavior.

---

## 8. Tutorial — build your first app end-to-end (≈30–45 min)

A small but real **Redis-backed URL shortener** (web). It exercises the entire
loop: brainstorm → spec → TDD → Redis modeling → web UI → Playwright test →
security → performance → docs → ship. Do it once and the workflow is yours.

### Step 0 — scaffold & open
```bash
./new-project.sh shortlink
cd ../shortlink
claude
```

### Step 1 — qualify (`/brainstorm`)
```
/brainstorm a URL shortener: paste a long URL, get a short code, visiting it redirects
```
Answer the agent's questions (who uses it, expected volume, custom codes?,
expiry?). It writes `docs/product/brief.md`. Keep scope tiny: create + redirect.

### Step 2 — spec (`/spec`)
```
/spec create-and-redirect
```
Review `docs/specs/create-and-redirect.md`. Make sure acceptance criteria are
testable, e.g.:
- *Given a valid URL, when I POST it, then I get a 7-char code.*
- *Given a known code, when I GET /:code, then I'm redirected (302) to the URL.*
- *Given an invalid URL, then I get 400.*

### Step 3 — plan test-first (`/plan-feature`)
```
/plan-feature create-and-redirect
```
The agent verifies current library versions with **Context7**, then lists
red→green→refactor steps. Approve, and let it write the **failing tests first**.

### Step 4 — implement
Let the agent implement the minimal code to pass each test. Watch the Redis
modeling — it should use the `redis-core` skill (e.g. a `String`/`Hash` keyed
`shortlink:<code>`, maybe a `TTL` for expiry, an atomic counter or random code).
Ask it to explain the data model; push back if it reaches for `KEYS`.

Run a local Redis if you haven't:
```bash
docker run -d -p 6379:6379 redis:latest
```

### Step 5 — a real browser test (Playwright)
Ask: *"add a Playwright test that creates a link in the UI and follows the
redirect"* — it'll use the `playwright-test` skill and the Playwright MCP.

### Step 6 — review
```
/code-review
/security-review
```
Confirm input validation (reject non-URLs, limit length), no open redirect, no
secrets. Fix what they find.

### Step 7 — ship
```
/ship
```
Tests + lint + types + build + dependency audit + **secret scan** + docs check.
If green, it proposes a Conventional Commit and asks before committing. Try
committing a fake secret on purpose once to watch the guard block it. 🙂

### Step 8 — document & push
```
/doc-sync
```
Make the `README.md` truly copy-paste runnable. Then push when you're ready:
```bash
git push -u origin main        # the guard scans the range first
```

You've now run the full professional loop on a real app.

---

## 9. Daily cheat sheet

**Launch / sessions**
```bash
claude                 # start in the current repo
claude -c              # continue the last session
claude --resume        # pick a past session
claude -p "…"          # headless one-shot (scripts/CI)
```

**In-session**
| Want to… | Do |
|---|---|
| Plan before editing | Shift+Tab → plan mode |
| See context usage | `/context` |
| Free up context mid-task | `/compact` |
| Start a fresh task | `/clear` |
| Pin a file | `@path/to/file` |
| Save a durable fact | start a line with `#` |
| Think harder | add "think hard" / "ultrathink" |
| Review code / security | `/code-review` / `/security-review` |
| Run your workflow | `/brainstorm` `/spec` `/plan-feature` `/ship` `/doc-sync` |
| See MCP / skills | `/mcp` / `npx skills list` |
| Track usage / limit | `npx ccusage@latest blocks --live` ([details](workspace-and-monitoring.md)) |
| Work on 2–3 projects | `claude --worktree <name>` (isolated branch per project) |

**When to `/clear` vs `/compact`**
- `/compact` — same task, conversation got long. Keeps a summary.
- `/clear` — new, unrelated task. Start clean (CLAUDE.md reloads automatically).

**Cost / context tips**
- Keep `CLAUDE.md` lean; put detail in `docs/` and `@`-mention on demand.
- Delegate big searches to subagents; use `rtk-cli`/`rg` to keep output small.
- Turn on `caveman` skill when you want terse, token-light replies.

**Troubleshooting**
| Symptom | Fix |
|---|---|
| `claude: command not found` | open a new terminal / `exec zsh -l` (PATH from native installer) |
| MCP server not responding | `/mcp` to re-auth; check the command runs standalone |
| Hook blocks a legit commit | it found a secret-shaped string — fix it, or allowlist in `.gitleaks.toml` |
| Skill not triggering | name it explicitly ("use the X skill"); `npx skills list` to confirm it's installed |
| Context feels "lost" | you probably `/clear`-ed or it `/compact`-ed; re-`@`-mention key files |

---

### Reference
- This kit: `claude-code-dev-setup` (run `./doctor.sh` anytime).
- Redis skills: `redis/agent-skills`, `fcenedes/redis_sa_skills`.
- Claude Code docs: <https://code.claude.com/docs>.
