---
description: Pre-push quality gate — tests, lint, types, build, audit, secrets, docs
argument-hint: [optional scope note]
---

Run the full pre-ship gate **before** proposing any commit or push. Detect the
stack from the repo (package.json / pyproject.toml / pom.xml / composer.json)
and run the equivalent of each step. Report each as PASS/FAIL with the real
command output. **Do not commit or push if anything fails** — stop and fix.

Scope note (optional): $ARGUMENTS

1. **Tests** — run the unit/integration suite. (`npm test` / `pnpm test` /
   `pytest` / `mvn test` …). Must be green.
2. **Lint** — (`eslint`/`npm run lint` / `ruff check` …).
3. **Types** — (`tsc --noEmit`/`npm run typecheck` / `mypy` …) if applicable.
4. **Build** — (`npm run build` / `mvn -q package` …) if applicable.
5. **Container image** — if `deploy/Dockerfile*` exists, **build** it in the VM
   (`docker build …`) to prove the deploy image builds (build only — **no push**).
   Deploying happens on the host via `deploy/gcp-deploy.sh` (see CLAUDE.md → *Isolated VM*).
6. **Dependency audit** — (`npm audit --omit=dev` / `osv-scanner` / `pip-audit`).
   Report High/Critical.
7. **Secret scan** — `gitleaks dir . --no-banner --redact` (or `gitleaks detect`).
   Must be clean.
8. **Docs check** — did behavior change? If so, confirm `README.md` (human) and
   `docs/specs/*` (agent) are updated. Flag anything stale.

Finish with a short checklist summary. If everything passes, propose a
Conventional Commit message and a one-line PR summary, then **ask** before
committing/pushing (never push unprompted).
