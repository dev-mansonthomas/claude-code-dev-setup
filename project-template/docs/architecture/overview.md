# {{PROJECT_NAME}} — Architecture overview

> How the pieces fit. Update when the shape changes.

## Context (C4 level 1)
What system is this, who/what does it talk to (users, external services)?

```
[ User ] --> [ {{PROJECT_NAME}} ] --> [ Redis ]
                       |
                       +--> [ external API ]
```
*(replace with a real diagram — DrawIO or the redis-excalidraw-diagrams skill)*

## Components (C4 level 2)
| Component | Responsibility | Tech |
|-----------|----------------|------|
| TODO | TODO | TODO |

## Data
- Stores: TODO (e.g., Redis — keys, types, TTLs, indexes)
- Data flow: request → … → response

## Cross-cutting
- AuthN/AuthZ: …
- Config & secrets: env vars / secret manager (never in code)
- Observability: logs, metrics, traces
- Performance notes: hot paths, caching strategy, expected load

## Key decisions
See `docs/adr/`.
