---
description: Bring human + agent docs back in sync with the current code
argument-hint: [area or feature, optional]
---

Reconcile the docs with reality. Focus area (optional): $ARGUMENTS

1. Compare the code against the docs and list what's **stale, missing, or wrong**
   across:
   - `README.md` — human, zero-assumed-knowledge: prerequisites, install, run,
     test, env vars, troubleshooting. A newcomer must succeed by copy-paste.
   - `docs/product/PRD.md` — problem/users/scope still accurate?
   - `docs/specs/*.md` — do specs match actual behavior?
   - `docs/architecture/*` — components, data flow, Redis keys/types.
   - `docs/adr/*` — any decision made recently that deserves an ADR?
   - `CLAUDE.md` — is the project entry-map current (commands, layout, gotchas)?

2. Show the proposed changes as a concise diff/summary first.
3. On confirmation, apply the updates. Verify any commands you document by
   running them. Don't invent behavior — if unsure, inspect the code.

Keep human docs and agent docs clearly separated and cross-link them.
