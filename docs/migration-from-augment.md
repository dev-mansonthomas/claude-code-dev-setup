# Migrating a project from Augment to Claude Code

Redis's Augment subscription ends **2026-06-30**. This is the handover playbook: for each project
built with Augment (Code / Intent), reconstruct the Claude Code **agent-doc tree** (`CLAUDE.md` +
`docs/`) and **capture in-flight work**, so Claude Code picks up where Augment left off.

## The problem (read first)

Augment keeps two kinds of state, and **only one is in your repo**:

1. **In the repo — portable.** `.augment-guidelines`, `.augment/` (rules), `.augmentignore`.
   These translate directly into Claude Code's `CLAUDE.md` + `.claude/settings.json`.
2. **In Augment's cloud — NOT in the repo, lost when access ends.** "Memories", the internal
   **task/todo list**, conversation history, accumulated understanding.

Claude Code **cannot fetch (2)** — it only sees your repo + git history. Therefore:

- **Before 2026-06-30, export from Augment what you can** (Step 0). This is the only *irreversible*
  deadline — everything else can be done later.
- The rest, Claude Code **reconstructs from the code + git history**. That is *inferred*, so it must
  be **grounded in the actual code and validated by you**, never invented.

## Step 0 — export from Augment *while you still have access* (per project, do this first)

In the Augment UI, copy into a scratch file at the project root named **`AUGMENT_CARRYOVER.md`**:
- the **open tasks / todo list / current plan** (the most perishable item);
- the **Memories** Augment shows for this workspace;
- any **User/Workspace Guidelines** not already in `.augment-guidelines`;
- one paragraph: *"what I was in the middle of."*

Keep secrets out of it. It's temporary scaffolding the prompt ingests, then you delete it.

## Step 1 — run the migration prompt in Claude Code

In the VM, at the project root (`ccvm <project>`), paste **the prompt in the last section** of this
file. It reconstructs the doc tree, ingests `AUGMENT_CARRYOVER.md`, captures pending work, runs the
build/tests to verify, and writes a migration report — flagging everything it *inferred*.

## Step 2 — validate & finish

- Read the generated `CLAUDE.md` + `docs/` and **correct anything inferred wrong** (you know the project).
- Confirm "how to build/run/test" really works (the prompt runs it — double-check).
- Once absorbed: **delete `AUGMENT_CARRYOVER.md`** and remove the translated `.augment*` artifacts.
- Commit on a branch, then push/PR/merge **from the host** (see [isolation.md](isolation.md)):
  `docs: migrate agent docs from Augment to Claude Code`.

Repeat per project. The prompt is stack-aware (PHP · Redis + Lua · MySQL · Python · AngularJS ·
Angular · TypeScript · Docker · Terraform · shell).

---

## The prompt (copy everything in the block below)

```text
You are taking over this project from Augment (Augment Code / Intent). Augment's subscription is
ending and its cloud state (memories, internal todo list) will be lost. Your job: reconstruct the
Claude Code agent-documentation tree from THIS repository (and from AUGMENT_CARRYOVER.md if present),
capture in-flight work, and leave the project ready for Claude Code — grounded in the real code,
never invented.

Ground rules:
- Base every statement on the actual code, config, and `git log` / `git branch`. When you infer,
  label it "(inferred — verify)". Never invent features, decisions, or status.
- Detect the stack(s) yourself (PHP, Python, Redis + Lua, MySQL, AngularJS/Angular, TypeScript,
  Docker, Terraform, shell) and document each one's REAL install/build/run/test commands. RUN them
  to confirm before writing "this is how it builds/tests"; if a command fails or you can't run it,
  say so explicitly.
- Ask me up to 5 clarifying questions ONLY where the code genuinely can't answer (product intent,
  priorities, ownership). Otherwise proceed without pausing.
- Do not commit or push — I review first.

Do this, in order:

1. INVENTORY. Map the top-level layout, the stack(s) and their entry points, services
   (docker-compose), data stores (MySQL schema, Redis usage — including any Lua scripts), CI, and
   any Augment artifacts (.augment-guidelines, .augment/, .augmentignore). Summarize in ~10 lines.

2. CARRY-OVER. If AUGMENT_CARRYOVER.md exists, read it: fold its guidelines into CLAUDE.md, its
   memories into the docs, its open tasks into the TODO (step 5). Translate any .augment-guidelines
   / Augment rules into CLAUDE.md conventions and .claude/settings.json.

3. RECONSTRUCT THE AGENT DOCS (create these, matching the Claude-Code-dev-setup layout):
   - CLAUDE.md — the entry map: what the project is, the stack, EXACT verified install/build/run/
     test commands, the module map (dir -> responsibility), key conventions, and gotchas.
   - docs/product/PRD.md — problem, users, scope (inferred from code/README/git; mark inferred).
   - docs/architecture/overview.md — components, data flow, the MySQL + Redis model, the role of any
     Lua scripts, external dependencies. Add a small mermaid diagram if it clarifies.
   - docs/specs/<feature>.md — one per significant feature you can identify: inputs, outputs, edge
     cases, and acceptance criteria reverse-engineered from the existing tests.
   - docs/adr/NNNN-title.md — for decisions visible in the code/history (datastore choice, Lua for
     atomicity, framework choices, etc.), with the "why" where discoverable.

4. TEST MAP. What is tested vs not. List the gaps — they become future specs/tasks.

5. PENDING WORK -> docs/TODO.md. Combine: open items from AUGMENT_CARRYOVER.md, plus TODO/FIXME/HACK
   comments, unfinished branches (`git branch`), failing or skipped tests, and anything half-built
   you notice. Group by area; mark severity (blocker / soon / nice-to-have).

6. docs/migration-status.md — a report: what you reconstructed; what is "(inferred)" and needs my
   confirmation; what could NOT be recovered (Augment cloud state); and the recommended next 3 actions.

7. VERIFY & SUMMARIZE. Run the build/tests you documented and paste the REAL output. Then give me a
   short summary plus your <=5 questions. Do not commit.
```

> Tip: this is a one-shot reconstruction. Afterwards, the normal loop applies —
> `/brainstorm → /spec → /plan-feature → … → /ship` (see the README), and `/doc-sync` keeps the docs
> in step with the code.
