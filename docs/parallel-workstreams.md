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

Open each stream in its own terminal — on macOS, **iTerm2 tabs or split panes work perfectly and you
do NOT need tmux**: a pane/tab is just host-side window layout, and each one runs an independent
`ccvm` → an independent VM session. (tmux/iTerm2 panes only matter for Claude's *agent-teams*
split-pane mode, which can't drive the host's iTerm2 from inside the VM anyway — irrelevant here.)

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

### Validate messaging actually works (do this once)

All sessions run in the same VM as the same user, so they should see each other — confirm it:

1. Two terminals: `ccvm <project> --worktree stream-a` and `ccvm <project> --worktree stream-b`.
2. In **A**: `/list-agents` → you should see **stream-b** (and A). Peer listed ⇒ discovery works.
3. In **A**: `@stream-b ping` (or "send stream-b a message: ping"). In **B** it surfaces in the inbox.
   Reverse to confirm both directions.

**Only works VM-session ↔ VM-session.** A `claude` running on the **host** is a different machine
from the VM (container↔host boundary, no bridge), so it will not appear in `/list-agents` — keep every
stream inside `ccvm`. Requires VM `claude` ≥ v2.1.224 (the VM is well past that).

## Overseeing many streams

- `claude agents` — a dashboard of running/background sessions (peek, attach, stop). Background
  sessions auto-isolate into their own worktrees.
- From inside a session, `/bg <task>` dispatches a background stream that reports back.

## Shipping each stream (host-only, as always)

Each worktree is its own branch, so ship them **independently** — never from the VM:

1. In the stream's session, write the PR body to `debug/git/pr-body.md`.
2. On the **host**: `git-pr-merge --branch <stream-branch> "<title>"`.

Streams merge in any order; `git-pr-merge` fast-forwards `main` each time.

### Conflicts between streams

The real parallel risk: two streams edit the same files, so the second to merge conflicts with the
now-updated `main`. `git-pr-merge` **never force-merges** — `gh pr merge` fails and it exits **6**.
Recover in the lagging stream's worktree:

```bash
git fetch origin main && git rebase origin/main   # resolve, git add, git rebase --continue
```

then re-run `git-pr-merge`. Spot collisions *early*, before they bite, with:

```bash
git diff --name-only origin/main...feat/<stream>   # per stream — overlapping files = risk
```

and `git-check` (kit tool) → `debug/git/git-check.json` for GitHub-vs-local state. `delta` (installed
in the VM) gives readable diffs and side-by-side conflict review during the rebase.

### Cleanup

`git-pr-merge` now **removes a merged stream's worktree automatically** when it's clean (it reports the
path as `worktreeRemoved`; a dirty worktree is left untouched with a warning). If you ever need to do
it by hand: `git worktree remove .claude/worktrees/<stream>`. The local branch ref may linger (the tool
won't force-delete possibly-unpushed commits) — drop it with `git branch -D feat/<stream>` when done.

## VM resource notes

All streams share the one VM: CPU/RAM, the ~19 GB root FS, and the 60 GB Docker disk. Parallel
installs/builds fill caches fast — run **`vm-clean`** if the root FS gets tight, and avoid many heavy
Docker builds at once (they compete for the Docker disk).

## Skills that help (already available)

No new install needed — `git worktree` is built in and `claude agents` ships with the VM's `claude`.
For methodology, the **`superpowers`** plugin (enabled globally) already provides:

- `superpowers:using-git-worktrees` — start isolated feature work in a worktree.
- `superpowers:dispatching-parallel-agents` — 2+ independent tasks in parallel.
- `superpowers:subagent-driven-development` — execute a plan's independent tasks in one session.

## When worktrees aren't enough

If streams must *continuously negotiate* over the **same files** (not just notify each other), consider
Claude's **experimental agent teams** (a lead spawns teammates with a shared task list + mailbox):
enable with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Caveats: teammates do **not** auto-isolate into
worktrees (you partition file ownership by hand), and it costs roughly N× the tokens for N teammates.
Reach for worktrees + messaging first; escalate to teams only for tightly-coupled work.
