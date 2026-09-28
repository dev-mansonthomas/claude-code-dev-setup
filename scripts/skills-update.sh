#!/usr/bin/env bash
# skills-update — refresh all globally-installed Agent Skills to their latest upstream.
#
# Runs the same source-refresh that `./03-vm-up.sh` now does: `git pull --ff-only` every repo in
# ~/.claude/skill-sources, re-link any new skills into ~/.claude/skills, and report old→new HEAD per
# source. Use it on demand between provisions.
#
# NOTE: third-party sources are pulled to their latest HEAD (not pinned) — a supply-chain action.
# Review changes if that matters to you (each source lives at ~/.claude/skill-sources/<owner>-<repo>).
set -euo pipefail

# Resolve this script's real directory even when invoked via a /usr/local/bin symlink (portable:
# BSD/macOS `readlink` has no -f, so follow the link chain by hand).
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE="$(cd -P "$(dirname "$src")" && pwd)"

exec bash "$HERE/20-skills.sh" "$@"
