# ADR 0001 — Record architecture decisions

- **Status**: Accepted
- **Date**: {{DATE}}

## Context
We want a lightweight, durable record of *why* significant technical decisions
were made — for humans joining later and for agents working in this repo.

## Decision
We use Architecture Decision Records (ADRs). Each significant decision gets a
numbered file here (`docs/adr/NNNN-title.md`) with: Context, Decision,
Consequences. One decision per file; never rewrite history — supersede instead.

## Consequences
- The "why" survives even when the people who made the call move on.
- Agents can read decisions instead of re-deriving or contradicting them.
- Small overhead per decision; worth it for anything non-obvious.

## Template for new ADRs
```
# ADR NNNN — <title>
- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD
## Context
## Decision
## Consequences
```
