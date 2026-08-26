#!/usr/bin/env bash
# skill-activate — activate Agent Skills for the CURRENT project (./.claude/skills), drawn from the
# skill packs cloned under ~/.claude/skill-sources (e.g. google/skills for GCP). Per-project so the
# GLOBAL context stays lean — activated skills are symlinks, gitignored (VM-local, not portable).
# Driven by the `/skills-review` command; re-run any time as the project's needs change.
#
# Usage:
#   skill-activate --list                # skills available to activate (in skill-sources, not global)
#   skill-activate <name> [<name>...]    # symlink named skills into ./.claude/skills
#   skill-activate --list-active         # what's active in this project
#   skill-activate --deactivate <name>…  # remove named skills from ./.claude/skills
set -uo pipefail

SRC_DIR="${SKILLS_SRC_DIR:-$HOME/.claude/skill-sources}"
GLOBAL_DIR="$HOME/.claude/skills"
PROJ_DIR=".claude/skills"

# Emit "name<TAB>dir<TAB>pack" for every skill (SKILL.md) under the cloned skill-sources.
index() {
  [ -d "$SRC_DIR" ] || return 0
  find "$SRC_DIR" -mindepth 2 -name SKILL.md -not -path '*/.git/*' 2>/dev/null | while IFS= read -r md; do
    d="$(dirname "$md")"; rel="${d#"$SRC_DIR"/}"; pack="${rel%%/*}"
    printf '%s\t%s\t%s\n' "$(basename "$d")" "$d" "$pack"
  done
}

list_available() {
  index | while IFS="$(printf '\t')" read -r name _ pack; do
    if [ -e "$GLOBAL_DIR/$name" ] || [ -L "$GLOBAL_DIR/$name" ]; then continue; fi  # already global
    printf '  %-48s %s\n' "$name" "($pack)"
  done | sort -u
}

list_active() {
  if [ -d "$PROJ_DIR" ]; then
    find "$PROJ_DIR" -mindepth 1 -maxdepth 1 \( -type l -o -type d \) ! -name '.gitignore' -printf '  %f\n' 2>/dev/null | sort
  fi
}

activate() {
  mkdir -p "$PROJ_DIR"
  [ -f "$PROJ_DIR/.gitignore" ] || printf '*\n!.gitignore\n' > "$PROJ_DIR/.gitignore"  # VM-local, keep out of git
  idx="$(index)"
  for n in "$@"; do
    hit="$(printf '%s\n' "$idx" | awk -F"$(printf '\t')" -v k="$n" '$1==k{print $2; exit}')"
    if [ -z "$hit" ]; then echo "  ✗ not found in skill-sources: $n (try: skill-activate --list)" >&2; continue; fi
    if [ -e "$PROJ_DIR/$n" ] || [ -L "$PROJ_DIR/$n" ]; then echo "  = already active: $n"; continue; fi
    if ln -s "$hit" "$PROJ_DIR/$n" 2>/dev/null; then echo "  ✓ activated: $n"; else echo "  ✗ could not link: $n" >&2; fi
  done
  echo "Active in $PROJ_DIR:"; list_active
}

deactivate() {
  for n in "$@"; do
    if [ -e "$PROJ_DIR/$n" ] || [ -L "$PROJ_DIR/$n" ]; then rm -rf "$PROJ_DIR/${n:?}"; echo "  ✗ deactivated: $n"; else echo "  = not active: $n"; fi
  done
}

case "${1:-}" in
  --list)        list_available ;;
  --list-active) list_active ;;
  --deactivate)  shift; [ "$#" -gt 0 ] || { echo "usage: skill-activate --deactivate <name>..." >&2; exit 2; }; deactivate "$@" ;;
  -h|--help)     sed -n '2,13{/^# /p;}' "$0" | sed 's/^# \{0,1\}//' ;;
  "")            echo "usage: skill-activate --list | <name>... | --list-active | --deactivate <name>..." >&2; exit 2 ;;
  --*)           echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  *)             activate "$@" ;;
esac
