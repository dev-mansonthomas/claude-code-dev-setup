# Brief — host git/GitHub utilities (`git-merge-pr` + `git-check`)

> One-page brief from `/brainstorm`. Next step: `/spec` the first slice. No code yet.

## Problem statement

The kit's security model splits work: Claude runs **in the VM** (no credentials) and can commit, but
**cannot push/PR/merge** — the human does that on the **host** (which holds the GitHub creds). Today
that means hand-running, for every change: `git push` → `gh pr create` → watch CI → `gh pr merge
--squash --delete-branch` → sync `main` → prune. It's repetitive and irritating. Two host utilities
automate it for **solo** work, and emit **JSON to a file the VM Claude can read**, closing the
host↔VM loop (host acts; VM agent learns the result).

## Target users & primary use case

- **Human (Thomas), on the host** — runs the utilities; reads the JSON (or a human line) to confirm.
- **The VM Claude (`ccvm`)** — the *primary consumer*: after it commits a branch, it asks the human
  to run the host utility, then **reads the JSON report file** (shared `~/Projects` mount) to confirm
  the merge / inspect repo state — same pattern as last-contact's `host-tools/deploy-logs.sh` → `debug/`.
- **Primary use case:** "Claude committed `feat/x`; land it on `main`." One host command does push →
  PR → CI → squash-merge → sync → prune, and writes a JSON report.

## Goals

- **`git-merge-pr`** (mutating): given an **already-committed** branch (default: current), `gh`/`git`:
  push → `gh pr create` (title+body args; reuse PR if one exists) → poll CI to green →
  `gh pr merge --squash --delete-branch` → checkout+pull `main` → prune. Writes a JSON report.
- **`git-check`** (read-only): snapshot of GitHub/remote state — open PRs, recent merged PRs, remote
  branches still present, recent `origin/main` log. Writes a JSON report.
- **Host-only**, **generic** across any repo under `~/Projects`, POSIX/bash-portable.
- **JSON-first output** (stable, documented schema) that's also human-skimmable, **written to a
  dedicated gitignored dir** in the repo + path printed; meaningful **exit codes**.
- **CI red** (`git-merge-pr`): no merge; report names the failing check(s) + the `gh run view …`
  command to fetch logs; non-zero exit.

## Non-goals

- **No commit creation** — the VM Claude already commits; the utility only pushes/PRs/merges.
- **No quality gate** — `/ship` (tests/lint/secrets/…) is assumed already run; these tools are pure
  git/GitHub automation.
- **No multi-contributor logic** — solo assumption: no review waits, no merge-queue, no rebase wars
  (conflicts are *reported*, not resolved).
- **Never run from the VM** (no creds); **never** force-push; **never** commit to `main`.

## Key constraints

- **Stack:** `bash` (host shell is zsh, scripts bash-portable), `gh` CLI (authed on host), `git`, `jq`.
- **Security:** host-only; `--squash --delete-branch`; base = `main` (auto-detected); no force-push.
- **Output contract (agent-facing):** JSON by default to `<repo>/<dedicated-dir>/<tool>.json`
  (overwritten each run for a predictable path the VM Claude can `Read`), echoed to stdout; a `--quiet`
  or `--human` toggle optional. Schema is **versioned** (a `schemaVersion` field) since agents depend on it.
- **No Redis / no perf concerns.** Latency bound only by CI wait (poll with backoff + a timeout).

## Top risks & open questions

1. **Naming** (you flagged it). Recommend `git-merge-pr` (mutating: push→PR→merge) + `git-check`
   (read-only inspection). `git-check` fits inspection, not the merge tool — confirm, or pick
   `git-merge-to-main` / other for util 1.
2. **Dedicated output dir** — where + gitignored? Options: reuse `debug/` (last-contact precedent), or
   a new `.git-tools/` / `.gitcheck/`. Must be created if missing and git-ignored.
3. **CI state detection** — distinguish *no checks configured* (→ merge) vs *pending* (→ wait, with
   timeout) vs *failed* (→ abort + report). Use `gh pr checks` / `gh run`; define poll interval + max wait.
4. **Idempotency / re-runs** — PR already open for the branch → detect & reuse, not error. Branch already
   pushed → fine. Re-run after a failed CI → re-poll, don't re-create.
5. **Branch protection** — solo repos likely have none, but required-checks could block merge; report
   clearly rather than `--admin`-forcing.

## Rough first slice (smallest worth building first)

**`git-merge-pr` happy path + clean CI-fail.** On the current (already-committed) branch:
push → `gh pr create <title> <body>` (reuse if exists) → poll `gh pr checks` → on **green**
`gh pr merge --squash --delete-branch` → checkout+pull `main` → prune; write
`{schemaVersion, tool, repo, branch, pr:{number,url}, ci:"success", mergedSha, baseUpdated, branchDeleted}`
to the dedicated dir + stdout, exit 0. On **red**: write `{… ci:"failed", failingChecks:[…], logsCmd}`,
print it, **do not merge**, exit non-zero. (`git-check` is the fast-follow second slice — mostly
read-only `gh`/`git` calls shaped into the same JSON contract.)

---

**Next step:** run `/spec` on the first slice (`git-merge-pr` happy path + CI-fail), settling the two
naming/dir questions there before implementation.
