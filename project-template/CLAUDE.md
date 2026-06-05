# {{PROJECT_NAME}} — project guide for Claude

> Entry map for any agent working in this repo. Keep it current.
> Global standards live in `~/.claude/CLAUDE.md`; this file adds project specifics.

## What this is
<!-- One paragraph: what {{PROJECT_NAME}} does and for whom. -->
TODO

## Stack & layout
- **Language / framework**: TODO
- **Package manager**: TODO
- **Tests**: TODO (how to run below)
- Key directories:
  - `src/` — TODO
  - `docs/` — agent-facing docs (PRD, specs, architecture, ADRs)
  - `tests/` — TODO

## How to run, test, build
```bash
# install
TODO
# run (dev)
TODO
# test
TODO
# lint / typecheck / build
TODO
```

## Conventions
- Follow the loop: qualify → `/spec` → `/plan-feature` (TDD) → implement →
  `/code-review` + `/security-review` → `/ship` → `/doc-sync`.
- Tests are written first. Don't mark work done without green tests.
- Verify library versions/APIs with the **Context7 MCP** before adding deps.
- Conventional Commits; branch off `main`; commit/push only when asked.

## Redis (if used)
- Connection via env var (never hard-code). Local dev DB: TODO.
- Key naming: `TODO:scheme`. Data structures used: TODO.
- Reach for the `redis-*` skills for modeling/ops questions.

## Gotchas / decisions
<!-- Things that surprised you; link to docs/adr/* for the "why". -->
- TODO

## Pointers
- Product brief: `docs/product/PRD.md`
- Feature specs: `docs/specs/`
- Architecture: `docs/architecture/overview.md`
- Decisions: `docs/adr/`
