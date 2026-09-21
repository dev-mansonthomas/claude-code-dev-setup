---
description: Discover an undocumented AI-built project — reconstruct docs + a task backlog from the code alone
argument-hint: [focus hint, optional]
---

You've been dropped into a project an AI built with **no handover** — no docs, no PRD, no task
list, maybe no README. Reconstruct the kit's doc layout and a task backlog **from evidence alone**
(code, git history, dependencies, tests, CI), grounding every claim by running the project.
Focus hint: $ARGUMENTS

Rules:
- **Evidence over assumption.** Every statement is **VERIFIED** (you ran it / read it) or
  **INFERRED** (a guess from patterns) — label the inferred ones. Never present a guess as fact.
  What only the original author could know → collect as a QUESTION, don't invent it.
- **Read-only until you understand it.** No refactoring or "fixing" in this pass.
- Follow the global loop/conventions (`~/.claude/CLAUDE.md`); stay inside this project.

Do this:

1. **Map the repo (read-only).** Inventory languages, manifests (`package.json`, `pyproject.toml`,
   `go.mod`, `pom.xml`, `*.tf`, `Dockerfile`), entry points, dir structure, configs, `.env*.example`,
   CI workflows, tests. Use `fd`/`rg`/`ast-grep`; delegate broad sweeps to a subagent to keep the
   main context lean.

2. **Mine the git history.** `git log --stat`, tags, branches, message patterns → the real timeline,
   abandoned directions, and the *implicit* task list: WIP commits, reverts, `TODO`/`FIXME`/`HACK`,
   stubs, skipped/failing tests, commented-out code.

3. **Establish ground truth — run it.** Install deps, build, run tests, lint/typecheck, start it if
   feasible. **Paste the REAL output.** Record the exact working commands (→ README "how to run").
   Anything that doesn't build/pass is a task, not a footnote.

4. **Reconstruct the docs** in the kit layout, each marking VERIFIED vs INFERRED:
   - `CLAUDE.md` — entry map: what it is, stack, how to run/test/build (step 3), key dirs, gotchas.
   - `README.md` — human-facing, zero-prior-knowledge, copy-paste to run (step 3).
   - `docs/product/PRD.md` — inferred problem / users / scope (flag inferred; confirm via questions).
   - `docs/architecture/overview.md` — components + how they fit, from the code.
   - `docs/adr/` — decisions you can *read off* the code (frameworks, stores, patterns) + evidence;
     mark the rationale INFERRED.
   - `docs/specs/` — a short contract per existing non-trivial feature (observed inputs/outputs/edges).

5. **Rebuild the task backlog** → `docs/tasks.md`: everything incomplete or risky from steps 1-3 —
   failing tests, TODO/FIXME, stubs, missing validation/authz, no error handling, absent tests,
   security smells, dependency/version risks. Rank correctness/security > performance > clarity.
   Don't fix yet.

6. **Report + ask.** Summarize what it is, its state (real build/test results), what you
   reconstructed vs what's still inferred. Then ask the human the **≤7 questions** only they can
   answer (intended users, priorities, non-obvious constraints, which INFERRED calls are wrong).
   Fold their answers back into the docs.

Then run **`/skills-review`** and proceed with the normal loop (`/brainstorm` → `/spec` → …).
