---
description: Turn a brief or request into an agent-facing feature spec
argument-hint: <feature name>
---

Write a precise, **agent-facing** specification for: $ARGUMENTS

First read `docs/product/brief.md` and any existing `docs/specs/*.md` and
`CLAUDE.md` for context. If the feature is ambiguous, ask up to 3 clarifying
questions before writing.

Then create `docs/specs/<kebab-feature-name>.md` using this structure:

```
# <Feature>

## Purpose
One paragraph: what this feature does and why.

## User stories / acceptance criteria
- As a <user>, I can <action> so that <value>.
- [ ] Given <state>, when <action>, then <observable result>.   (testable)

## Inputs & outputs
Explicit shapes: request/response, function signatures, data structures,
Redis keys/types touched (with naming).

## Behavior & edge cases
Happy path, then every edge case and error condition + expected handling.

## Out of scope
What this spec deliberately does NOT cover.

## Test plan
The unit/integration/e2e tests that prove the acceptance criteria.

## Dependencies & risks
Libraries (check latest stable via Context7), services, and the riskiest part.
```

Keep it concrete enough that another agent could implement it without guessing.
Acceptance criteria MUST be testable. End by recommending `/plan-feature
<feature>`. Do not implement yet.
