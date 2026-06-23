# Host git/GitHub utilities — `git-merge-pr` & `git-check`

## Purpose

Two **host-only** CLI utilities that close the host↔VM loop for **solo** repos. The VM Claude
(`ccvm`) commits a branch but has no credentials to publish it; today the human hand-runs
push→PR→watch-CI→merge→sync→prune for every change. `git-merge-pr` automates that whole chain;
`git-check` reports current GitHub/remote state. Both emit a **machine-readable JSON report written
to `debug/git/<tool>.json`** (in the current repo, on the shared mount) so the VM Claude can `Read`
it to confirm/inspect — plus the same JSON to stdout for the human.

## User stories / acceptance criteria

- As the human on the host, I can run `git-merge-pr "<title>" "<body>"` to take the current
  already-committed branch all the way to merged-on-`main`, without hand-running 6 commands.
- As the VM Claude, I can `Read debug/git/git-merge-pr.json` after the human runs the tool, to learn
  the PR number/URL, CI result, merged SHA, and whether the branch was pruned.
- As the human/agent, I can run `git-check` to get one JSON snapshot of open PRs, recent merges,
  remote branches, and recent `main` history.

Testable criteria (`[ ]`):
- [ ] Given a repo with a committed feature branch checked out and green CI, when `git-merge-pr "t"`
      runs, then the PR is squash-merged, the remote+local branch deleted, local `main` fast-forwarded,
      and `debug/git/git-merge-pr.json` contains `ok:true, ci:"success", pr.number, mergedSha`. Exit 0.
- [ ] Given the branch's CI fails, when `git-merge-pr` runs, then **no merge happens**, the JSON has
      `ok:false, ci:"failed", failingChecks:[…], logsCmd`, the message names the failing check, and the
      exit code is non-zero (5).
- [ ] Given an open PR already exists for the branch, when `git-merge-pr` runs, then it **reuses** that
      PR (no duplicate) and proceeds.
- [ ] Given the PR was already merged, when `git-merge-pr` re-runs, then it reports `alreadyMerged:true`,
      still syncs/prunes, and exits 0 (idempotent).
- [ ] Given the current branch IS the base (`main`), when `git-merge-pr` runs, then it refuses with a
      usage error (exit 2) and does not push.
- [ ] Given `gh` is not authenticated (or git/gh/jq missing), when either tool runs, then it emits
      `ok:false, error.code:"preconditions"` and exits 3 without mutating anything.
- [ ] Given any repo, when either tool runs, then `debug/git/.gitignore` exists (`*` + `!.gitignore`)
      so reports are never committed; and the JSON is also printed to stdout.
- [ ] `git-check` output validates against the documented schema and performs **zero** mutations.
- [ ] `bash -n` and `shellcheck` are clean for both scripts.

## Inputs & outputs

### Invocation
- `git-merge-pr [--branch <name>] [--base <name>] [--timeout <sec>] [--poll <sec>] [--no-footer] [--no-stdout] <title> [body]`
  - `title` required (positional 1); `body` optional (positional 2). `--branch` defaults to the current
    branch; `--base` defaults to the repo's default branch (`gh repo view --json defaultBranchRef`,
    fallback `main`). `--timeout` default 600, `--poll` default 8 (seconds). `--no-footer` skips the
    `🤖 Generated with Claude Code` body footer (appended by default to match kit convention).
- `git-check [--limit <N>] [--no-stdout]` — `--limit` default 8 (merged PRs & main-log depth).
- Both are installed on `PATH` as bare commands (no `.sh`, like `ccvm`); because they're named
  `git-*`, `git merge-pr …` / `git check` also work as git subcommands.

### Output location & format
- JSON written (overwrite) to `<repo-root>/debug/git/<tool>.json` and echoed to stdout (unless
  `--no-stdout`). `<repo-root>` = `git rev-parse --show-toplevel`. The tool creates `debug/git/` and a
  `debug/git/.gitignore` containing `*` and `!.gitignore` (reports never committed, dir self-contained).

### Shared JSON envelope (schemaVersion 1)
```jsonc
{
  "schemaVersion": 1,
  "tool": "git-merge-pr" | "git-check",
  "ok": true,
  "repo": "owner/name",
  "base": "main",
  "generatedAt": "2026-06-23T10:00:00Z",
  // ...tool-specific fields...
  "error": { "code": "usage|preconditions|push|ci|merge|conflict", "message": "..." } // only when ok:false
}
```

### `git-merge-pr` success fields
```jsonc
{
  "branch": "feat/x",
  "pushed": true,
  "workingTreeDirty": false,           // warn-only: only committed commits are published
  "pr": { "number": 14, "url": "https://github.com/owner/name/pull/14", "reused": false },
  "ci": "success",                      // success | failed | timeout | none
  "checks": [ { "name": "lint", "conclusion": "success" } ],
  "merged": true, "alreadyMerged": false,
  "mergedSha": "abc1234",
  "baseUpdated": true,                  // local main fast-forwarded
  "branchDeleted": { "remote": true, "local": true }
}
```
On CI failure (`ok:false`): `ci:"failed"`, `failingChecks:[{name,conclusion,detailsUrl}]`,
`logsCmd:"gh run view <run-id> --log-failed"`, `merged:false`.

### `git-check` fields
```jsonc
{
  "openPRs":        [ { "number": 0, "title": "", "headRefName": "", "isDraft": false, "url": "" } ],
  "recentlyMerged": [ { "number": 0, "title": "", "headRefName": "", "mergedAt": "", "url": "" } ],
  "remoteBranches": [ { "name": "feat/x", "merged": true } ],   // merged = already in base
  "staleBranches":  [ "feat/x" ],                                // remote branches already merged into base
  "mainLog":        [ { "sha": "abc1234", "subject": "feat: …" } ]
}
```

### Data sources (no Redis; no app data)
- `git push -u origin <branch>`, `git rev-parse`, `git checkout`, `git pull --ff-only`, `git fetch -p`,
  `git ls-remote --heads origin`, `git log origin/<base>`, `git branch --merged`.
- `gh pr view/create/merge/list/checks`, `gh repo view`, `gh auth status`, `gh run view` (all `--json`).
- `jq` for shaping/validation.

## Behavior & edge cases

**`git-merge-pr` happy path:** preconditions → resolve branch/base → `git push -u` → reuse-or-create PR
(append footer) → poll `gh pr checks` until conclusion → on green `gh pr merge --squash --delete-branch`
→ `git checkout <base> && git pull --ff-only` → `git fetch -p` + delete local feature branch → write
JSON, exit 0.

Edge cases / handling:
- **Not a git repo / git|gh|jq missing / `gh` not authed** → `error.code:"preconditions"`, exit 3, no mutation.
- **On the base branch** or **no commits ahead of base** → `error.code:"usage"`, exit 2, no push.
- **Working tree dirty** → proceed (only committed commits are pushed), set `workingTreeDirty:true` (warn).
- **Push rejected (non-fast-forward / remote ahead)** → `error.code:"push"`, exit 4, **never** force-push.
- **PR already open for branch** → reuse (`pr.reused:true`), continue.
- **PR already merged** → `alreadyMerged:true`, still sync/prune, exit 0.
- **CI: no checks configured** → `ci:"none"`, merge proceeds. **pending/in_progress** → poll every `--poll`s
  up to `--timeout`s. **failed** → `ci:"failed"`, abort, report failing checks + `logsCmd`, exit 5.
  **timeout** → `ci:"timeout"`, no merge, exit 5.
- **Merge blocked** (branch protection / required review / not mergeable / conflict) → read reason from
  `gh`, `error.code:"merge"|"conflict"`, exit 6, **no `--admin` force**.
- **Re-run after fixing CI** → re-poll the existing PR, don't recreate.

**`git-check`** is strictly read-only: gathers the sources above, shapes them into the schema, computes
`staleBranches` (remote heads already merged into base), writes JSON, exit 0. Network/gh errors →
`ok:false, error.code:"preconditions"`, exit 3.

**Exit codes:** 0 ok · 2 usage · 3 preconditions · 4 push · 5 ci · 6 merge/conflict.

## Out of scope

- Creating commits or running a quality gate (`/ship` is assumed already passed).
- Multi-contributor flows: review waits, merge queues, conflict *resolution* (conflicts are reported).
- Running from the VM, force-push, committing to `main`, `--admin` override of protections.
- Auto-deleting stale remote branches (`git-check` only *reports* them; deletion could be a later flag).
- **Moving last-contact's deploy logs to `debug/deploy/`** — a separate last-contact change (its
  `deploy-logs.sh` + CLAUDE.md ref + `.gitignore`), tracked outside this kit spec.

## Test plan

- **Static:** `bash -n` + `shellcheck` clean (wired into `make lint`).
- **Unit (stubbed):** a test harness prepends a temp dir to `PATH` with fake `gh`/`git` scripts that
  emit canned JSON, then asserts the tool's JSON + exit code for: happy path · CI `none` · CI `failed`
  · CI `timeout` · PR-already-open · PR-already-merged · on-base (usage) · not-a-repo · gh-not-authed ·
  push-rejected · merge-blocked. Assertions parse the JSON with `jq` (validate envelope + key fields).
- **Schema:** a `jq` assertion that every run's output has `schemaVersion, tool, ok, repo, generatedAt`
  and (when `ok:false`) `error.code`.
- **`git-check`:** stub `gh`/`git`, assert the documented shape and that no mutating git/gh command is
  invoked (the stubs fail loudly if `push`/`merge`/`fetch -p`/`branch -d` are called).
- **Integration (manual, optional):** against a throwaway GitHub repo — real branch → `git-merge-pr` →
  assert PR merged + JSON; then `git-check` shows it under `recentlyMerged`.

## Dependencies & risks

- **Tools:** `git`, `gh` (≥ 2.95, present), `jq` (≥ 1.8, present). These are CLI tools, not libraries —
  no Context7 lookup needed; `gh`'s `--json`/`--jq` API is stable. No new runtime deps.
- **Riskiest part:** **CI-state detection** — cleanly distinguishing *no checks* vs *pending* vs *failed*
  vs *timeout* across `gh pr checks` / `statusCheckRollup` output shapes, and being **idempotent on
  re-runs** (reuse PR, don't duplicate; handle already-merged). Second risk: correct, side-effect-free
  stubbing in tests so the unit suite is trustworthy without hitting real GitHub.

---

**Next step:** `/plan-feature host-git-utilities` — plan the **first slice** (`git-merge-pr` happy path
+ clean CI-fail + the shared JSON envelope/output), TDD via the stubbed harness; `git-check` follows.
