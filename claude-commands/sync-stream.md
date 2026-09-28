---
description: Safely rebase a parallel work-stream's worktree onto its base and resolve conflicts — backup-tagged, worktree-only, never force
argument-hint: [base branch, default main]
---

Bring **this** work stream's branch up to date with its base and resolve any conflicts — safely, so the
repo can't be left in a bad state. Base: $ARGUMENTS (default `main`). Run from inside the stream's
worktree session (`ccvm <project> --worktree <stream>`), either proactively or when `git-pr-merge`
reported `conflict: true` in `debug/git/git-pr-merge.json`.

Rules (why this can't trash the repo):
- **Worktree-only + non-destructive.** Operate on the current branch in *this* worktree only. NEVER
  `push --force`, `reset --hard`, or delete branches (the auto-mode classifier blocks these anyway).
- **Escape hatch:** `git rebase --abort` returns you to the exact pre-rebase state and is always safe.
  The backup tag (step 2) is extra insurance the *user* can restore by hand if ever needed.
- Base is kept current by `git-pr-merge`'s fast-forward on the host (shared `.git`), so **no network or
  credentials** are needed — rebase onto the LOCAL base.

Do this:

1. **Confirm context.** `git rev-parse --abbrev-ref HEAD` must be the *stream* branch, not the base
   (if it's the base, stop — you're not in a stream worktree). Ensure `git status` is clean; commit or
   stash WIP first.
2. **Tag a recovery point.** `git tag -f "backup/$(git rev-parse --abbrev-ref HEAD)-prerebase"` and tell
   the user it exists ("abort or this tag restores everything").
3. **Preview the overlap** (no network — base is already local): `git log --oneline <base>..HEAD` (your
   commits) and `git diff --name-only HEAD...<base>` (files that also changed on the base = the likely
   conflict set). Show it before touching anything.
4. **Rebase.** `git rebase <base>`. For each conflict: show it (`delta` renders it), resolve **minimally,
   preserving BOTH sides' intent**, `git add`, `git rebase --continue`. If a hunk is genuinely ambiguous,
   **ask the user** — don't guess. If it turns messy, `git rebase --abort` and report; do not improvise.
5. **Verify.** Run the stream's tests / lint / build (per the project `CLAUDE.md`) and **paste the real
   output**. Red = not done.
6. **Hand off to ship (host-only).** Summarize what conflicted and how you resolved it, then: write the
   PR body to `debug/git/pr-body.md` and tell the user to run `git-pr-merge --branch <stream> "<title>"`
   on the host. After it merges, drop the tag: `git tag -d "backup/<stream>-prerebase"`.
