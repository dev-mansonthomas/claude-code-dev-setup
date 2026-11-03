#!/usr/bin/env bash
# skills-update — review and apply upstream updates to the globally-installed Agent Skills.
#
# For every skill source in ~/.claude/skill-sources: fetch the latest upstream, show what changed
# (files, skills added/removed/changed), and ask before applying. Nothing changes until you answer y.
# Skills are third-party and unpinned, and a skill is instructions Claude follows (it can bundle
# scripts), so updates are never applied behind your back.
#
# Usage: skills-update [--check | --yes] [-h | --help]
#   (no option)  review each source with updates and ask [y/N]; needs a terminal.
#   --check      only report which sources have updates waiting; change nothing.
#   --yes, -y    apply every update without asking (same effect as SKILLS_AUTO_APPLY=1).
#
# Exit status: 0 when every source was fetched/handled; 1 if any source failed (offline, deleted or
# private repo, unreadable clone) — so a script or a glance at $? can tell "nothing updated" from
# "already up to date".
#
# Environment variables: see `20-skills.sh --help` (SKILLS_AUTO_APPLY, SKILLS_SRC_DIR, NO_COLOR).
set -euo pipefail

# Resolve this script's real directory even when invoked via a PATH symlink (portable:
# BSD/macOS `readlink` has no -f, so follow the link chain by hand).
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE="$(cd -P "$(dirname "$src")" && pwd)"

# Own help (the header above), not 20-skills.sh's.
case "${1:-}" in
  -h|--help) sed -n '2,/^set -/{/^set -/!p;}' "$src" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# --review --strict are the defaults for this command; a later --check/--yes from the user overrides
# --review because 20-skills.sh applies options in order.
exec bash "$HERE/20-skills.sh" --review --strict "$@"
