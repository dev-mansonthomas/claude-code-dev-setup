---
description: Break a spec into a small, test-first (TDD) implementation plan
argument-hint: <feature name>
---

Produce a **test-first** implementation plan for: $ARGUMENTS

Read `docs/specs/<feature>.md` (ask which spec if unclear) plus the relevant
source so the plan fits the existing architecture and reuses what's there.

Before planning, **verify library versions/APIs with the Context7 MCP** for
anything new you'll pull in — don't assume from memory.

Output an ordered task list where most tasks follow **red → green → refactor**:

1. For each acceptance criterion, the **failing test** to write first (file +
   what it asserts).
2. The **minimal implementation** to make it pass (file + function, reusing
   existing utilities — name them with paths).
3. Any **refactor** once green.

Also call out:
- Files to create vs modify (concrete paths).
- The riskiest step and how you'll de-risk it.
- How you'll run the tests (exact command) and what "done" looks like.

Keep steps small and independently verifiable. Then ask whether to start with
task 1 (write the first failing test). Do not implement until confirmed.
