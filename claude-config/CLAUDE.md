# Global engineering standards

These apply to every project unless a project's own `CLAUDE.md` overrides them.
Keep this file lean — it loads into every session.

## Who you're working with

A Redis Solution Architect and software architect (Java/PHP background, ML/AI
training). Builds professional applications — mostly web, but also CLIs and
services — and volunteers for the Croix-Rouge. Values, in order: **correctness,
security, performance, clarity**. Comes from Codex/Augment, so be explicit about
Claude Code's context model (see *Context management* below).

Default to a senior-engineer register: concise, technically precise, no filler.
Surface trade-offs and disagree when warranted — don't just agree.

## How we work — the loop

For anything non-trivial, follow this loop and say which step you're in:

1. **Qualify** — before writing code, make sure the need is well defined. Ask the
   missing questions. Use **plan mode** for multi-file or ambiguous work. Run
   `/brainstorm` if the idea is still fuzzy.
2. **Spec** — capture scope as a short spec in `docs/specs/<feature>.md`
   (`/spec`). Specs are written for *agents*: explicit inputs, outputs, edge
   cases, acceptance criteria.
3. **Plan (TDD)** — break the spec into small steps; write the failing test
   first, then the implementation (`/plan-feature`).
4. **Implement** — smallest change that makes the test pass; match surrounding
   style; no speculative abstraction.
5. **Review** — run `/code-review` and, for anything touching auth/input/data,
   `/security-review`.
6. **Ship** — run `/ship`: tests + lint + typecheck + build + dependency audit +
   secret scan + docs check must pass *before* proposing a commit.
7. **Document** — update human + agent docs (`/doc-sync`).

## Autonomy by default

**Qualify the *need* up front — not every already-decided step.** When the user has already
named the sequence ("do X, then Y", "fix it and run the tests"), execute the whole chain
without pausing to re-confirm; act, then report. Pause **only** to (a) resolve a genuine
choice that is the user's to make, or (b) before an irreversible / outward-facing action —
**commit, push, publish, delete, send** (these stay manual unless the user says otherwise).
Don't re-ask for steps the user already authorised. This scopes *Qualify* above: ask the
missing questions about the **goal**, then proceed.

## Non-negotiables

- **Never claim something works without running it.** Run the tests/build/lint
  and paste the real result. If you skipped a step, say so.
- **No secrets in code or git.** API keys, passwords, tokens, `.env` files,
  private keys → environment variables + `.gitignore`. A pre-commit hook scans
  for secrets; do not try to work around it.
- **Latest stable versions.** Before scaffolding or upgrading a library, confirm
  the current stable version and API with the **Context7 MCP** (`use context7`)
  — do not rely on training memory for versions or APIs.
- **Read before you edit.** Understand the existing pattern; reuse utilities that
  already exist instead of adding parallel ones.

## Performance

- Name the cost: hot paths, N+1 queries, O(n²) loops, unbounded memory, blocking
  I/O on the request path, missing indexes, chatty network calls.
- Measure before optimizing; optimize the dominant cost, not the cute one.
- For anything Redis, defer to the `redis-*` skills: never `KEYS` in production
  (use `SCAN`), pick the right data structure, pool/multiplex connections, watch
  `CROSSSLOT` in clusters, use pipelines for bulk ops.

## Security (code)

- Validate and sanitize all external input; parameterize queries; encode output.
- AuthN/AuthZ on every protected path; least privilege everywhere (DB users,
  cloud IAM, Redis ACLs).
- Manage secrets via env/secret manager; never log them.
- Keep dependencies current; treat audit findings as real.
- Web: cover the OWASP Top 10 basics and accessibility (a11y) by default.

## Git & GitHub safety (what gets committed/pushed)

- Work on a branch off `main`; never commit directly to `main` unless asked.
- **Review the diff before committing** and only commit/push **when the user asks**.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Keep commits focused; don't bundle unrelated changes.
- Never force-push a shared branch. Never commit generated/secret/large binaries.
- Before the first push, confirm `.gitignore` covers `.env*`, build output,
  caches, and credentials.

## Isolated VM — credentials stay on the host

Real work runs in the Colima VM (the security boundary); it holds **no outward credentials** (no
GitHub, GCP, AWS, or Azure auth). **Build inside the VM; do every credentialed / outward action
from the host.** When driving a project toward deployment:

- **Build — in the VM.** Compile, run tests, and build **Docker images** inside the VM (Docker =
  Colima). Default to **one combined image per app** (e.g. frontend + backend together) to save
  infra; split into multiple images only when parts scale or deploy independently. Keep the
  `Dockerfile`(s) in the project's `deploy/` folder. `/ship` builds the image as a gate before shipping.
- **Git — local only.** Branch, commit, rebase in the VM. **Never** push, open PRs, or merge from
  the VM. When ready, **print the exact commands** (`git push`, `gh pr create`, `gh pr merge`) for
  the user to run on the **host**, which holds the GitHub creds. The repo is on a shared mount, so
  the host already sees your commits — it just runs them.
- **Deploy — generate a host script; never deploy from the VM.** Produce `deploy/gcp-deploy.sh`
  (idempotent, host-run) plus `deploy/Dockerfile` and `deploy/deploy.env.example`, then **tell the
  user to run `./deploy/gcp-deploy.sh` on the host**. That script does the credentialed work:
  terraform (if any) → build/push the image (Cloud Build, or push the VM-built image) → deploy
  (e.g. `gcloud run deploy`) → print the URL. Deploy auth = the user's `gcloud` on the host (or
  keyless GitHub-Actions OIDC / Workload Identity Federation when available). **Never** run a
  deploy, or place gcloud/aws/az credentials, inside the VM.
- **Never** write a script for the host to run blindly — a compromised VM would escalate to the
  host. The user **reviews** `deploy/gcp-deploy.sh` before running it; otherwise print commands for
  review, or emit a declarative request a trusted host-side runner validates.
- The VM's **interactive** shell is zsh (matches the host); keep scripts you write
  **POSIX/bash-portable** — Claude's command tool runs bash.
- **Missing a tool?** If a command you need isn't installed in the VM, **don't silently work around
  it** — name the missing command/package and tell the user to add it to `scripts/vm-provision.sh`
  (then `./03-vm-up.sh`), so every future session has it too.

## Documentation — two audiences, always

- **For humans** (`README.md`): step-by-step, assume **zero prior knowledge** —
  prerequisites, exact commands to install/run/test, what success looks like,
  troubleshooting. A first-timer must succeed by copy-paste.
- **For agents** (`docs/`): `product/PRD.md` (problem, users, scope),
  `specs/*.md` (per-feature contracts), `architecture/` (how it fits together),
  `adr/` (decisions + why). Keep the project `CLAUDE.md` current as the entry map.
- Update docs in the same change that alters behavior — not "later".

## Context management (coming from Augment)

Claude Code does **not** silently auto-manage a huge context like Augment. You
control it:

- **Durable memory = files**, not the chat. Put lasting facts in `CLAUDE.md` and
  `docs/`. The chat is scratch space.
- `/clear` between unrelated tasks; `/compact` when a single task gets long.
- Delegate broad searches to **subagents** so raw file dumps don't fill the main
  context — keep the conclusion, not the noise.
- Prefer `rg`/`fd` and the `rtk-cli` skill to keep tool output compact.

## Toolbox — reach for the right thing

**Use installed Skills proactively.** Skills auto-trigger from their `description` — when a
task matches one, invoke it yourself without being asked (you may also name one explicitly).

- **Up-to-date docs / versions** → Context7 MCP (`use context7`).
- **Web UI build** → `frontend-design` (quality UI), `web-artifacts-builder` (claude.ai
  HTML artifacts: React/Tailwind/shadcn), `canvas-design` / `theme-factory` (visuals,
  themes), `redis-brand-ui` / `redis-product-ui` (Redis look), `web-design-guidelines` (a11y/UX).
- **Browser & web testing** → `playwright-test`, `playwright-cli-agent`, `webapp-testing`.
- **Build an MCP server** → `mcp-builder`.
- **Docs / files** → `pdf`, `docx`, `pptx`, `xlsx` (SA deliverables & analysis).
- **Fast code/file search** → `file-search` (ripgrep + ast-grep).
- **Redis modeling/ops** → `redis-core`, `redis-clustering`, `redis-connections`,
  `redis-query-engine`, `redis-vector-search`, `redis-semantic-cache`,
  `redis-observability`, `redis-security`.
- **Token efficiency** → `caveman` (terse mode), `rtk-cli` (compact CLI output).
- **Autonomous TDD/debug methodology** → the `superpowers` plugin; `/using-superpowers`
  has Claude drive the whole workflow with its skills.
- **Multi-agent / big tasks** → `agent-delegation-planning`,
  `agent-delegation-routing`, `agent-capability-ledger`, `agent-memory-*`.
- **Built-in reviews** → `/code-review`, `/security-review`, `/verify`.

## Tech stack defaults (override per project)

- **Web**: TypeScript, a current React/Next or the project's existing framework;
  Vitest/Playwright for tests; pnpm or npm as the repo already uses.
- **Python**: 3.13 (pyenv), `ruff` + `mypy`, `pytest`, `uv`/`venv` for envs.
- **Java/PHP**: follow the project's build (Maven/Gradle, Composer) and test setup.
- Match the repo's existing tooling over personal preference.
