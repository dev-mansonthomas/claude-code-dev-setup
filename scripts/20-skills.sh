#!/usr/bin/env bash
# 20-skills.sh — install Agent Skills GLOBALLY for Claude Code (~/.claude/skills).
#
# We clone the source repos and symlink each skill into ~/.claude/skills ourselves.
# Why not `npx skills -g -a claude-code`? Its global path for Claude Code is unreliable
# (open bugs: it can target the project-only "PromptScript" agent and skips creating the
# ~/.claude/skills symlink). Cloning + symlinking is deterministic, non-interactive and
# idempotent: anything already present is left untouched — no scary "failed" messages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "Agent Skills (global -> ~/.claude/skills)"

has git || { warn "git not found — skipping skills."; exit 0; }

SKILLS_DIR="$HOME/.claude/skills"
SRC_DIR="${SKILLS_SRC_DIR:-$HOME/.claude/skill-sources}"
mkdir -p "$SKILLS_DIR"

present_now=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')
info "$present_now skill(s) already in ~/.claude/skills."

# Format: "<git-url>|<filter>|<marker>"
#   <filter>  empty = all skills in the repo; else space-separated allowlist of names
#   <marker>  a representative skill; if it's already present, the whole repo is skipped
SKILL_SOURCES=(
  "https://github.com/fcenedes/redis_sa_skills||caveman"
  "https://github.com/redis/agent-skills||redis-core"
  "https://github.com/anthropics/skills|frontend-design pdf canvas-design theme-factory web-artifacts-builder mcp-builder webapp-testing|web-artifacts-builder"
  "https://github.com/netresearch/file-search-skill|file-search|file-search"
)

linked=0; skipped=0

link_one() {  # link_one <skill_dir> — symlink into ~/.claude/skills if not already there
  local sdir="$1" name target
  name="$(basename "$sdir")"
  target="$SKILLS_DIR/$name"
  [[ -e "$target" || -L "$target" ]] && return 0   # already present — leave it
  if ln -s "$sdir" "$target" 2>/dev/null; then
    ok "linked $name"; linked=$((linked + 1))
  else
    warn "could not link $name"
  fi
}

for entry in "${SKILL_SOURCES[@]}"; do
  url="${entry%%|*}"; rest="${entry#*|}"; filter="${rest%%|*}"; marker="${rest##*|}"
  repo="$(basename "$url" .git)"

  if [[ -e "$SKILLS_DIR/$marker" || -L "$SKILLS_DIR/$marker" ]]; then
    ok "$repo: already present (skipping)"
    skipped=$((skipped + 1))
    continue
  fi

  dir="$SRC_DIR/$repo"
  info "$repo: installing${filter:+ (only: $filter)}..."
  mkdir -p "$SRC_DIR"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --quiet --ff-only 2>/dev/null || warn "could not update $repo (using existing clone)"
  elif ! git clone --quiet --depth 1 "$url" "$dir" 2>/dev/null; then
    warn "could not clone $url — skipping $repo."
    continue
  fi

  # Each skill is a directory containing SKILL.md. Filtered sources (one named skill,
  # e.g. massgen's file-search) may bury it deep, so search deeper there; --all sources
  # stay shallow to avoid matching nested example SKILL.md files.
  maxd=3; [[ -n "$filter" ]] && maxd=12
  while IFS= read -r skillmd; do
    sdir="$(dirname "$skillmd")"; name="$(basename "$sdir")"
    if [[ -n "$filter" ]]; then
      case " $filter " in *" $name "*) ;; *) continue ;; esac
    fi
    link_one "$sdir"
  done < <(find "$dir" -mindepth 2 -maxdepth "$maxd" -name SKILL.md -not -path '*/.git/*' 2>/dev/null)
done

ok "Skills done: $linked newly linked, $skipped source(s) already present."
info "List: ls ~/.claude/skills   |   verify: ./02-doctor.sh"
[[ -d "$SRC_DIR" ]] && info "Sources cloned in $SRC_DIR (update later: git -C $SRC_DIR/<repo> pull)."
exit 0
