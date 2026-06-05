---
description: Qualify a fuzzy idea into a one-page brief before any code is written
argument-hint: [one-line idea, optional]
---

You are helping qualify and shape an idea **before** any implementation. Do not
write code or scaffold anything in this command.

Idea (may be empty — if so, ask for it first): $ARGUMENTS

Work through this as a short, focused interview. Ask **one cluster of questions
at a time**, wait for answers, and keep it tight:

1. **Problem & outcome** — what problem, for whom, and what does success look
   like? What's explicitly out of scope?
2. **Users & context** — who uses it, how often, on what (web/CLI/service)?
   Any volume, latency, or availability expectations?
3. **Constraints** — language/stack, hosting, data (esp. Redis usage), security
   /compliance, deadlines, budget.
4. **Risks & unknowns** — the 2–3 things most likely to make this hard or wrong.

When you have enough, produce a **one-page brief** and save it to
`docs/product/brief.md` (create the path if needed):

- Problem statement (2–3 sentences)
- Target users & primary use case
- Goals / non-goals (bullet lists)
- Key constraints (stack, data, security, performance targets)
- Top risks & open questions
- A rough first slice (the smallest thing worth building first)

End by recommending the next step: run `/spec` on the first slice. Do **not**
start building.
