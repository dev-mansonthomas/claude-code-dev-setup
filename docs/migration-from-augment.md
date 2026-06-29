# Migrating a project from Augment to Claude Code

Redis's Augment subscription ends **2026-06-30**. This is the handover playbook: for each project
built with Augment (Code / Intent), do a **two-phase** migration that loses nothing and lands the
project in this kit's conventions.

## The problem

Augment keeps state in two places, and **only one is in your repo**:

1. **In the repo — portable.** `.augment-guidelines`, `.augment/` (rules), `.augmentignore`.
2. **In Augment's cloud — lost when access ends.** "Memories", the internal **task/todo list**,
   conversation history, accumulated understanding of the project.

Claude Code can't reach (2). So the migration runs in **two phases**:

- **Phase 1 — inside Augment** (before 2026-06-30): Augment has all the context, so let it **dump
  everything it knows** into files in the repo — its memories, its in-progress todo list, decisions,
  and a first draft of the docs. This is the perishable step with the hard deadline.
- **Phase 2 — inside Claude Code (`ccvm`)** (any time after): Claude Code is the **authoritative**
  pass. Augment's dump is a *source, not the truth* — Claude Code **re-grounds every claim against
  the real code + git**, **adapts it to this kit's conventions** (the global `CLAUDE.md` already
  defines our security model and loop — the project docs must fit that, not Augment's), asks you the
  gaps, and finalizes the agent-doc tree.

> Why split it: Phase 1 rescues what's only in Augment's head before it's gone; Phase 2 corrects
> Augment's drift/hallucinations and aligns everything to how *we* work.

---

## Phase 1 — run this **in Augment** (before 2026-06-30)

Paste into Augment (Code or Intent), at the project. It writes a `handover/` folder.

```text
You are handing this project off to another AI coding assistant, and your access to this workspace
is ending soon — your memories and internal task state will be permanently lost. Capture EVERYTHING
you know that a fresh assistant could NOT reconstruct from the code alone, into files in this repo,
so the handover is lossless. Be exhaustive and HONEST about status (never mark "done" what isn't).
No secrets. Put everything under a new handover/ folder.

Write:

1. handover/STATE.md — the perishable stuff, first:
   - your current task list / plan in progress, verbatim from your internal todo/intent state
     (done / in-progress / next);
   - "what I was in the middle of" and the immediate next step;
   - open questions and blockers you were tracking.

2. handover/MEMORY.md — everything in YOUR memory about this project that isn't obvious from the
   code: decisions and their rationale, constraints, agreed conventions, gotchas, dead-ends already
   ruled out, domain knowledge, owners/stakeholders, "why it is the way it is".

3. handover/DECISIONS.md — key technical decisions (datastore, Redis + Lua choices, framework,
   infra) in ADR style: context → decision → consequences.

4. A first-draft doc set (the next assistant will refine and verify it):
   - handover/PRD.md — problem, users, scope (in / out).
   - handover/ARCHITECTURE.md — components, data flow, the MySQL + Redis model, the role of any Lua
     scripts, services, external dependencies.
   - handover/FEATURES.md — each significant feature: what it does, inputs/outputs, current status,
     and which tests cover it.

5. handover/GUIDELINES.md — your active guidelines/rules for this project (standards, do/don't),
   including anything from .augment-guidelines or your rules files.

When unsure, say so explicitly rather than guessing.
```

Commit `handover/` (it's now in the repo, safe from the deadline). Repeat per project before June 30.

---

## Phase 2 — run this **in Claude Code (`ccvm <project>`)** (any time after)

Paste into Claude Code at the project root. It turns `handover/` into the kit's doc tree, verified
and adapted.

```text
This project is migrating from Augment to Claude Code. Augment left a handover/ folder (STATE.md,
MEMORY.md, DECISIONS.md, PRD.md, ARCHITECTURE.md, FEATURES.md, GUIDELINES.md). Turn that handover —
cross-checked against the ACTUAL code — into this kit's Claude Code agent-doc structure, adapted to
our conventions.

Ground rules:
- handover/ is a SOURCE, not the truth: Augment can be stale or wrong. VERIFY every claim against
  the real code, config, and git history. Where they disagree, trust the code and note the
  discrepancy. Mark anything still unverifiable "(inferred — verify)".
- Detect the stack(s) (PHP, Python, Redis + Lua, MySQL, AngularJS/Angular, TypeScript, Docker,
  Terraform, shell) and RUN the build/tests to confirm the "how to run" before documenting it.
- Adapt to THIS setup's conventions (they differ from Augment's):
  * The global ~/.claude/CLAUDE.md already defines our security model (build in the VM; git + deploy
    from the host; no credentials in the VM) and the brainstorm→spec→plan→ship→deploy loop. The
    PROJECT CLAUDE.md must NOT restate that — reference it and add only project-specifics.
  * Translate handover/GUIDELINES.md into the project CLAUDE.md conventions + .claude/settings.json
    allow-list, dropping anything already covered globally.
- Ask me up to 5 questions only where neither the code nor the handover answers. Do NOT commit.

Produce (matching the kit layout):
- CLAUDE.md — project entry map: what it is, the stack, EXACT verified install/build/run/test
  commands, the module map (dir → responsibility), conventions, gotchas. Reference the global
  security/workflow model; don't repeat it.
- docs/product/PRD.md      (from handover/PRD.md, re-grounded in the code)
- docs/architecture/overview.md  (from handover/ARCHITECTURE.md, verified vs code; mermaid if useful)
- docs/specs/<feature>.md  per feature (from handover/FEATURES.md + the tests: inputs, outputs, edge
  cases, acceptance criteria)
- docs/adr/NNNN-title.md   (from handover/DECISIONS.md)
- docs/TODO.md             (from handover/STATE.md + TODO/FIXME/HACK + unfinished branches + failing/
  skipped tests; grouped by area, severity-tagged)
- docs/migration-status.md — report: what came from the handover, what you verified, what CONFLICTED
  with the code (and how you resolved it), what's still inferred, and the recommended next 3 actions.

Finally: run the build/tests you documented and paste the REAL output, then summarize and ask your
<=5 questions.
```

---

## Validate & finish (per project)

- Review the generated `CLAUDE.md` + `docs/` — fix anything inferred wrong (you know the project).
- Confirm the documented build/run/test actually works.
- Delete `handover/` once absorbed; remove translated `.augment*` artifacts.
- Commit on a branch, then push/PR/merge **from the host** (see [isolation.md](isolation.md)):
  `docs: migrate agent docs from Augment to Claude Code`.

After this, the normal loop applies — `/brainstorm → /spec → /plan-feature → … → /ship → deploy`,
with `/doc-sync` keeping docs in step with the code.

---

## No access to the original assistant? — code-only recovery (single phase)

If access to the original agent is already gone (Augment subscription ended, etc.), **Phase 1 is
impossible** — there's no memory to dump. Skip the two phases above and reconstruct **from the code +
git history alone**, in one pass inside `ccvm <project>`. The honest cost: the *why* (decisions,
rationale, dead-ends, in-flight intent) that lived only in the old agent's head is **unrecoverable** —
this prompt infers what it can, marks every inference, and lists the gaps for you.

Paste into Claude Code at the project root:

```text
This project was built with another AI agent whose memory and notes are gone — there is NO handover/
folder, only the code, the git history, and whatever docs/config are already in the repo. Reconstruct
this kit's agent-doc structure from the CODE ALONE, then review it. Be HONEST: the rationale, the
decisions, the dead-ends and the in-flight intent that lived only in the old agent's head are LOST —
infer conservatively, tag every inference "(inferred — verify)", and collect what only I can answer.

1. UNDERSTAND (read-only first). Detect the stack(s) and layout; map dir -> responsibility; infer the
   product's purpose and features from the code, the tests, the README, and the git history (commits,
   branches, tags). Then RUN the install/build/test commands to confirm how it actually runs — paste
   the REAL output.

2. TOOLCHAIN INVENTORY — this is the to-do I'll act on to update the VM. Detect every runtime/tool
   this project needs and its REQUIRED version, from: .nvmrc / .node-version / package.json "engines";
   pyproject.toml "requires-python" / .python-version; go.mod (go directive); pom.xml / build.gradle
   (Java version, toolchain); composer.json "require.php"; *.tf "required_version" + required_providers;
   .tool-versions / .sdkmanrc / rust-toolchain.toml; Dockerfile(s) (base image + apt installs); CI
   workflows; README prerequisites. For each, check what THIS VM already provides (you are inside it —
   `command -v <tool>` / `<tool> --version`) and classify: present & compatible / present but WRONG
   version / ABSENT. Flag where different projects of mine would need DIFFERENT versions of the same
   runtime (that needs a per-project version manager, not just an install).

3. WRITE the kit's docs, grounded only in what you verified. Reference the global ~/.claude/CLAUDE.md
   security & workflow model — do NOT restate it.
   - CLAUDE.md — entry map: what it is, the stack, the EXACT verified install/build/run/test commands,
     the module map (dir -> responsibility), conventions, gotchas.
   - docs/product/PRD.md — problem, users, scope (inferred from code/tests; mark the assumptions).
   - docs/architecture/overview.md — components, data flow, data model, external deps (mermaid if useful).
   - docs/specs/<feature>.md per significant feature — inputs, outputs, edge cases, acceptance
     criteria, and which tests cover it.
   - docs/adr/NNNN-title.md — decisions you can INFER from the code (datastore, framework, infra) in
     ADR style, each clearly tagged "(reconstructed — verify)".
   - docs/TODO.md — from TODO/FIXME/HACK comments + failing/skipped tests + unfinished branches.
   - docs/migration-status.md — what you recovered, what is inferred, what is UNRECOVERABLE (the lost
     "why"), the recommended next 3 actions, AND a "## Toolchain & VM gaps" section: a table
     [ tool | required version (+ where detected) | this VM has | verdict OK / wrong-version / MISSING ]
     plus a copy-pasteable "VM provisioning request" — the exact runtimes/versions to add to the VM,
     flagging any that need a per-project version manager because my projects diverge.

4. REVIEW the existing code (there is no prior review context). Run /code-review, then
   /security-review. Record findings in docs/TODO.md, severity-tagged. Do NOT fix yet — just surface.

5. SYNC. Run /doc-sync so the human README and the agent docs match the code.

Finally: summarize, **print the "VM provisioning request" block verbatim** (so I can paste it straight
back to you to update the VM), then ask me up to 5 questions — only where neither the code nor the git
history answers (the gaps that genuinely need the original author). Do NOT commit.
```

Then **Validate & finish** as above: review the generated docs (you still know the project), confirm
the documented build/test works, then commit on a branch and push/PR/merge from the host
(`git-pr-merge "docs: reconstruct agent docs from code"`).
