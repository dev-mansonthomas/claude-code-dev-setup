# Parallel work streams (several Claude sessions at once)

Everything here runs inside the one always-on Colima VM via `ccvm`. **Parallelism = several terminals,
each running `ccvm`, all as separate `claude` sessions in the same VM.** They share the VM's
`~/.claude`, so they discover and message each other over a **local Unix socket** — nothing extra to
install, nothing through Anthropic's servers. Two complementary building blocks:

- **git worktrees** isolate *files* (each stream = its own working dir + branch, shared `.git`).
- **cross-session messaging** circulates *information* between those isolated sessions.

## The model: one worktree per stream

Claude Code has native worktrees (v2.1.198+). `ccvm` forwards the flag:

```bash
ccvm <project> --worktree <stream>
```

- Creates/enters a worktree at `<project>/.claude/worktrees/<stream>` — under `~/Projects`, so it's on
  the mount and reachable in the VM.
- Branches from `origin/HEAD` by default (a clean base). To branch from your current local HEAD
  instead, set `"worktree": { "baseRef": "head" }` in the project's `.claude/settings.json`.
- Cleanup: a named worktree with no changes is swept after `cleanupPeriodDays`; force it with
  `git worktree remove <path>`.

One terminal per stream, e.g. the admin app's threads:

```bash
ccvm fleet-admin --worktree sinistres      # terminal 1
ccvm fleet-admin --worktree obd-geoloc     # terminal 2
ccvm fleet-admin --worktree gps-live       # terminal 3
```

Two separate apps (e.g. `admin` vs `reservation`) → same idea, one `ccvm <repo>` per repo.

> `ccvm` only forwards a conservative charset (`A-Za-z0-9 . _ / = -`) to `claude`, so keep stream
> names simple (`gps-live`, not `gps live`). Anything else is refused rather than run.

### Propagate `.env` into each worktree

Worktrees don't copy gitignored files. Put a **`.worktreeinclude`** at the project root (gitignore-style
patterns); each new worktree gets those files copied in. A pattern only applies if the file is **also**
gitignored (tracked files are never duplicated):

```
.env
.env.*
```

New projects created from the kit template already ship this file.

## Keep the shared data model in sync

Streams that share a Redis model must not drift. Keep **one contract doc** — e.g.
`docs/REDIS_SCHEMA.md` (key names, structures, TTLs, Stream/event formats) — and reference it from the
project `CLAUDE.md` so every session starts from the same truth. Treat editing it like changing an API.

## Cross-session messaging (v2.1.224+)

All streams run in the same VM, so messaging is local and private:

- `/list-agents` — list the other running sessions.
- Claude messages another session **automatically** when it makes a change that affects it (e.g.
  "changed the geoloc event format on the Redis Stream"); you can also ask it to, or `@<session>`.
- Inbound handling: `"crossSessionInbound": "accept" | "hold" | "refuse"` in settings.

Use messaging for **notices** ("a breaking change landed"); use the shared schema doc for the durable
**contract**. They're complementary, not alternatives.

## Overseeing many streams

- `claude agents` — a dashboard of running/background sessions (peek, attach, stop). Background
  sessions auto-isolate into their own worktrees.
- From inside a session, `/bg <task>` dispatches a background stream that reports back.

## Shipping each stream (host-only, as always)

Each worktree is its own branch, so ship them **independently** — never from the VM:

1. In the stream's session, write the PR body to `debug/git/pr-body.md`.
2. On the **host**: `git-pr-merge --branch <stream-branch> "<title>"`.

Streams merge in any order; `git-pr-merge` fast-forwards `main` each time. Rebase a long-lived stream
on the updated `main` when it falls behind.

## VM resource notes

All streams share the one VM: CPU/RAM, the ~19 GB root FS, and the 60 GB Docker disk. Parallel
installs/builds fill caches fast — run **`vm-clean`** if the root FS gets tight, and avoid many heavy
Docker builds at once (they compete for the Docker disk).

## When worktrees aren't enough

If streams must *continuously negotiate* over the **same files** (not just notify each other), consider
Claude's **experimental agent teams** (a lead spawns teammates with a shared task list + mailbox):
enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Caveats: teammates do **not** auto-isolate into
worktrees (you partition file ownership by hand), and it costs roughly N× the tokens for N teammates.
Reach for worktrees + messaging first; escalate to teams only for tightly-coupled work.
