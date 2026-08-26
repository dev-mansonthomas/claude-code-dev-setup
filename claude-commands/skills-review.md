---
description: Evaluate this project and activate only the Agent Skills it needs (per-project, on demand)
argument-hint: [domain hint, optional]
---

Review THIS project and activate only the Agent Skills it actually needs — **per-project**, so the
global context stays lean (every activated skill adds its description to every session). Optional
focus hint: $ARGUMENTS

Do this:

1. **Understand the project's real domains (read-only).** Read `CLAUDE.md`, `docs/product/brief.md`
   (the `/brainstorm` output) if it exists, the dependency/build manifests (`package.json`,
   `pyproject.toml`, `go.mod`, `pom.xml`, `*.tf`, `Dockerfile`, `requirements.txt`), and the
   code/README. Infer the concrete technologies in play — e.g. GCP (Cloud Run, BigQuery, GKE,
   Cloud SQL…), React/Vite, Python, Redis, Terraform.

2. **See what's available to activate:** run `skill-activate --list`. These are skills cloned under
   `~/.claude/skill-sources` but NOT loaded globally (currently the `google/skills` GCP pack, ~124).
   The always-on skills (`redis-*`, `frontend-design`, `caveman`, …) are already global — don't
   re-propose those.

3. **Propose a SMALL, relevant subset.** Map the project's real needs to available skills and pick a
   handful that clearly apply — e.g. for a Cloud Run deploy: `cloud-run-basics`, `gcloud`,
   `cloud-build-basics`, a `cloud-logging`/`cloud-monitoring` skill; add a GCP-database skill only if
   the project actually uses that database. **Never bulk-activate a whole category** — that's the
   token bloat we're avoiding. One line of justification per proposed skill.
   - If the project needs a skill that isn't in the local packs, point to the **`find-skills`** skill
     to discover installable ones, rather than guessing.

4. **Ask the user to confirm or adjust** the list. Do NOT activate without an explicit yes.

5. **Activate the confirmed set:** `skill-activate <name> [<name>...]` (symlinks them into
   `./.claude/skills`, gitignored). Then show the result with `skill-activate --list-active`.

This is **re-runnable any time** the project evolves — re-run to add newly-relevant skills. To drop
one that's no longer needed: `skill-activate --deactivate <name>`.
