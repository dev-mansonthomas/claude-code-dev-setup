#!/usr/bin/env bash
# 20-skills.sh — install and refresh Agent Skills GLOBALLY for Claude Code (~/.claude/skills).
#
# Source repos are shallow-cloned into ~/.claude/skill-sources/<owner>-<repo> and every skill
# directory (one containing SKILL.md) is symlinked into ~/.claude/skills. We do this ourselves rather
# than with `npx skills -g -a claude-code`: its global path for Claude Code is unreliable (it can
# target the project-only "PromptScript" agent and skips creating the ~/.claude/skills symlink).
#
# UPDATES ARE GATED. Sources are third-party and unpinned, and a skill is instructions (sometimes
# bundled scripts) that Claude follows the moment it is linked. So an already-cloned source is
# fetched and compared, but new upstream content is only APPLIED after review. Three modes:
#   --check   (default; used by 01-setup.sh and by VM provisioning, which have no terminal and never
#             prompt) fetch, report which sources have updates waiting, change nothing.
#   --review  (what `skills-update` runs) per source: show what changed (files, added/removed
#             skills), then ask [y/N]. Needs a terminal; without one it falls back to --check.
#   --yes     apply every update without asking (same as SKILLS_AUTO_APPLY=1).
# A first install (no clone yet) is applied directly: choosing the sources is the user's decision.
#
# Usage: 20-skills.sh [--check | --review | --yes] [--strict] [-h | --help]
#   --strict   exit 1 if any source failed to clone/fetch/apply. Default: always exit 0, so a flaky
#              network never aborts 01-setup.sh or VM provisioning. `skills-update` passes --strict.
#
# Environment variables:
#   SKILLS_AUTO_APPLY=1   default mode becomes --yes: updates are applied UNREVIEWED. Default 0.
#   SKILLS_SRC_DIR=PATH   where sources are cloned. Default ~/.claude/skill-sources.
#   AUTO_YES              does NOT approve skill updates (it only answers the kit's generic prompts).
#   NO_COLOR              any non-empty value disables colours.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
# Script mode only: abort on unexpected errors. When sourced (tests) the caller's shell is untouched.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then set -e; fi

# A source that became private or was deleted must fail fast, not sit waiting for a password.
export GIT_TERMINAL_PROMPT=0

SKILLS_DIR="$HOME/.claude/skills"
SRC_DIR="${SKILLS_SRC_DIR:-$HOME/.claude/skill-sources}"

MODE=check          # check | review | yes
STRICT=0
if [[ "${SKILLS_AUTO_APPLY:-0}" == "1" ]]; then MODE=yes; fi

# Format: "<git-url>|<filter>"
#   <filter>  empty = every skill in the repo; else a space-separated allowlist of skill names.
SKILL_SOURCES=(
  "https://github.com/fcenedes/redis_sa_skills|"
  "https://github.com/redis/agent-skills|"
  "https://github.com/anthropics/skills|frontend-design pdf docx pptx xlsx canvas-design theme-factory web-artifacts-builder mcp-builder webapp-testing skill-creator"
  "https://github.com/vercel-labs/agent-skills|web-design-guidelines react-best-practices"
  "https://github.com/vercel-labs/skills|find-skills"
  "https://github.com/netresearch/file-search-skill|file-search"
)

# CLONE-ONLY domain packs: cloned but NOT linked globally -> 0 context cost until activated.
# `/skills-review` + `skill-activate` link a relevant subset PER-PROJECT on demand (e.g. GCP work).
# Format "<git-url>|<clone-dir>" — explicit dir since google/skills & vercel-labs/skills share the
# basename "skills". (Shallow clone; the repo's `plugins/` submodules are intentionally not fetched.)
CLONE_ONLY_SOURCES=(
  "https://github.com/google/skills|google-skills"   # ~124 Google Cloud/GCP skills
)

linked=0; updated=0; pending=0; FAILED=0
SYNC=""; SYNC_OLD=""; SYNC_NEW=""

usage() { sed -n '2,/^set -/{/^set -/!p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- seams (tests redefine these) --------------------------------------------------------------
is_tty() { [[ -t 0 && -t 1 ]]; }
confirm_apply() {   # confirm_apply <name> — explicit "yes" required; anything else keeps the old copy
  local ans
  printf '   Apply this update to %s? [y/N] ' "$1"
  read -r ans || ans=""
  [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# git over the network: abort a stalled transfer (<1 KB/s for 20 s) rather than hang provisioning.
_git_net() { git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 "$@"; }
_last_line() { printf '%s\n' "$1" | sed -n '$p'; }

# --- naming ------------------------------------------------------------------------------------
# Clone dir = "<owner>-<repo>", NOT the bare repo name, so sources sharing a basename never collide
# (anthropics/skills vs vercel-labs/skills, redis/agent-skills vs vercel-labs/agent-skills).
src_name() {      # works for https://host/owner/repo[.git] and file:///path/owner/repo
  local p="${1%/}"; p="${p%.git}"
  local repo="${p##*/}" rest="${p%/*}"
  printf '%s-%s' "${rest##*/}" "$repo"
}
legacy_name() { local p="${1%/}"; p="${p%.git}"; printf '%s' "${p##*/}"; }
norm_url()    { local u="${1%/}"; printf '%s' "${u%.git}"; }

# --- linking -----------------------------------------------------------------------------------
link_one() {  # link_one <skill_dir> — symlink into ~/.claude/skills unless a working link exists
  local sdir="$1" name target
  name="$(basename "$sdir")"
  target="$SKILLS_DIR/$name"
  if [[ -e "$target" || -L "$target" ]]; then return 0; fi
  if ln -s "$sdir" "$target" 2>/dev/null; then
    ok "linked $name"; linked=$((linked + 1))
  else
    warn "could not link $name"
  fi
}

link_skills() {  # link_skills <clone_dir> <filter>
  local dir="$1" filter="$2" maxd=3 skillmd sdir name
  # Filtered sources (one named skill) may bury it deep; unfiltered ones stay shallow so nested
  # example SKILL.md files aren't picked up.
  if [[ -n "$filter" ]]; then maxd=12; fi
  while IFS= read -r skillmd; do
    sdir="$(dirname "$skillmd")"; name="$(basename "$sdir")"
    if [[ -n "$filter" ]]; then
      case " $filter " in *" $name "*) ;; *) continue ;; esac
    fi
    link_one "$sdir"
  done < <(find "$dir" -mindepth 2 -maxdepth "$maxd" -name SKILL.md -not -path '*/.git/*' 2>/dev/null)
}

repoint_links() {  # repoint_links <old_dir> <new_dir> — fix ~/.claude/skills links into a moved clone
  local link t
  for link in "$SKILLS_DIR"/*; do
    if [[ ! -L "$link" ]]; then continue; fi
    t="$(readlink "$link")"
    case "$t" in
      "$1"/*) if [[ -e "$2/${t#"$1"/}" ]]; then ln -sfn "$2/${t#"$1"/}" "$link"; fi ;;
    esac
  done
}

prune_dangling() {  # drop links into SRC_DIR whose target vanished upstream; link_one then re-creates
  local link t
  for link in "$SKILLS_DIR"/*; do
    if [[ ! -L "$link" || -e "$link" ]]; then continue; fi
    t="$(readlink "$link")"
    case "$t" in
      "$SRC_DIR"/*) rm -f "$link"; info "removed dead link $(basename "$link") (gone upstream)" ;;
    esac
  done
}

# Installs made before the owner-repo naming have the clone under the bare repo name, with live
# symlinks into it. Adopt it (rename + re-point the links) so it gets refreshed like any other.
migrate_legacy() {  # migrate_legacy <url>
  local url="$1" new_dir legacy_dir origin
  new_dir="$SRC_DIR/$(src_name "$url")"; legacy_dir="$SRC_DIR/$(legacy_name "$url")"
  if [[ "$legacy_dir" == "$new_dir" || ! -d "$legacy_dir/.git" ]]; then return 0; fi
  origin="$(git -C "$legacy_dir" config --get remote.origin.url 2>/dev/null || true)"
  # A different repo may own that bare name (e.g. 'skills'): only adopt a clone of THIS source.
  if [[ "$(norm_url "$origin")" != "$(norm_url "$url")" ]]; then return 0; fi
  if [[ ! -e "$new_dir" ]]; then
    if mv "$legacy_dir" "$new_dir"; then
      info "migrated legacy clone $(basename "$legacy_dir") → $(basename "$new_dir")"
    else
      warn "could not rename $legacy_dir → $new_dir"; return 0
    fi
  else
    warn "legacy clone $legacy_dir duplicates $new_dir — remove it when convenient: rm -rf $legacy_dir"
  fi
  repoint_links "$legacy_dir" "$new_dir"
}

# --- update preview -----------------------------------------------------------------------------
skill_changes() {  # skill_changes <dir> <filter> — "+name" added, "-name" removed, "~name" modified
  local dir="$1" filter="$2" st path name sign
  while IFS=$'\t' read -r st path; do
    case "$path" in */SKILL.md) ;; *) continue ;; esac
    name="$(basename "$(dirname "$path")")"
    if [[ -n "$filter" ]]; then
      case " $filter " in *" $name "*) ;; *) continue ;; esac
    fi
    case "$st" in A) sign="+" ;; D) sign="-" ;; *) sign="~" ;; esac
    printf '%s%s\n' "$sign" "$name"
  done < <(git -C "$dir" diff --no-renames --name-status HEAD FETCH_HEAD 2>/dev/null)
}

show_update() {  # show_update <name> <dir> <changes> <nfiles>
  local name="$1" dir="$2" changes="$3" nfiles="$4" stat nlines
  printf '\n%s── %s: %s → %s  (%s file(s) changed)%s\n' "$C_BOLD" "$name" "$SYNC_OLD" "$SYNC_NEW" "$nfiles" "$C_RESET"
  if [[ -n "$changes" ]]; then
    printf '   skills: %s\n' "$(printf '%s' "$changes" | tr '\n' ' ')"
  else
    printf '   skills: none added/removed/changed (supporting files only)\n'
  fi
  stat="$(git -C "$dir" diff --stat HEAD FETCH_HEAD 2>/dev/null || true)"
  nlines="$(printf '%s\n' "$stat" | wc -l | tr -d ' ')"
  printf '%s\n' "$stat" | sed -n '1,30p' | sed 's/^/   /'
  if [[ "$nlines" -gt 30 ]]; then printf '   ... (%s more lines)\n' "$((nlines - 30))"; fi
  printf '   full diff: git -C %s diff HEAD FETCH_HEAD\n' "$dir"
  printf '   %sA skill is instructions Claude follows (and may bundle scripts): read the diff before accepting.%s\n' "$C_YELLOW" "$C_RESET"
}

# --- sync one source ----------------------------------------------------------------------------
# sync_repo <url> <dir> <filter> — clone when absent, else fetch and apply per MODE. Never exits.
# Sets SYNC to: cloned | uptodate | updated | pending | declined | failed  (SYNC_OLD/SYNC_NEW = short SHAs).
sync_repo() {
  local url="$1" dir="$2" filter="$3" name out old_full new_full changes nfiles sk apply=0 decision=""
  name="$(basename "$dir")"
  SYNC=""; SYNC_OLD=""; SYNC_NEW=""
  mkdir -p "$SRC_DIR"

  if [[ ! -d "$dir/.git" ]]; then
    info "$name: cloning${filter:+ (only: $filter)}..."
    if out="$(_git_net clone --quiet --depth 1 "$url" "$dir" 2>&1)"; then
      SYNC=cloned
    else
      warn "$name: clone failed — $(_last_line "$out")"; SYNC=failed
    fi
    return 0
  fi

  # HEAD (not a branch name) so an upstream default-branch rename or a force-push still resolves.
  if ! out="$(_git_net -C "$dir" fetch --quiet --depth 1 origin HEAD 2>&1)"; then
    warn "$name: fetch failed, kept the current copy — $(_last_line "$out")"; SYNC=failed; return 0
  fi
  if ! old_full="$(git -C "$dir" rev-parse HEAD 2>/dev/null)" \
     || ! new_full="$(git -C "$dir" rev-parse 'FETCH_HEAD^{commit}' 2>/dev/null)"; then
    warn "$name: unreadable clone — remove it to re-clone: rm -rf $dir"; SYNC=failed; return 0
  fi
  SYNC_OLD="${old_full:0:7}"; SYNC_NEW="${new_full:0:7}"
  if [[ "$old_full" == "$new_full" ]]; then SYNC=uptodate; return 0; fi

  changes="$(skill_changes "$dir" "$filter")"
  nfiles="$(git -C "$dir" diff --no-renames --name-only HEAD FETCH_HEAD 2>/dev/null | wc -l | tr -d ' ')"
  case "$MODE" in
    yes) apply=1 ;;
    review)
      if is_tty; then
        show_update "$name" "$dir" "$changes" "$nfiles"
        if confirm_apply "$name"; then apply=1; else decision=declined; fi
      else
        warn "$name: --review needs a terminal; falling back to --check"
      fi ;;
  esac

  if [[ "$apply" == 1 ]]; then
    # Mirrors are read-only copies of upstream, so reset (not pull --ff-only): this survives
    # force-pushes, and the prune keeps the depth-1 clone from accumulating old history.
    if out="$(git -C "$dir" reset --hard --quiet FETCH_HEAD 2>&1)"; then
      git -C "$dir" reflog expire --expire=now --all >/dev/null 2>&1 || true
      git -C "$dir" gc --prune=now --quiet >/dev/null 2>&1 || true
      SYNC=updated
    else
      warn "$name: could not apply the update — $(_last_line "$out")"; SYNC=failed
    fi
    return 0
  fi

  SYNC="${decision:-pending}"
  if [[ "$SYNC" == pending ]]; then
    sk="$(printf '%s' "$changes" | tr '\n' ' ')"; sk="${sk% }"
    info "$name: update waiting $SYNC_OLD → $SYNC_NEW ($nfiles file(s); skills: ${sk:-none})"
  fi
  return 0
}

tally() {  # tally <name> — fold the last sync_repo result into the run counters
  case "$SYNC" in
    cloned)   ok "$1: cloned" ;;
    uptodate) ok "$1: up to date ($SYNC_OLD)" ;;
    updated)  ok "$1: updated $SYNC_OLD → $SYNC_NEW"; updated=$((updated + 1)) ;;
    declined) info "$1: update kept for later (declined)"; pending=$((pending + 1)) ;;
    pending)  pending=$((pending + 1)) ;;
    failed)   FAILED=$((FAILED + 1)) ;;
  esac
}

final_rc() { if [[ "$STRICT" == 1 && "$FAILED" -gt 0 ]]; then echo 1; else echo 0; fi; }

summary() {
  local msg="Skills done: $linked newly linked, $updated source(s) updated"
  if [[ "$pending" -gt 0 ]]; then msg="$msg, $pending with updates waiting"; fi
  if [[ "$FAILED" -gt 0 ]]; then msg="$msg, $FAILED FAILED"; fi
  if [[ "$FAILED" -gt 0 ]]; then warn "$msg"; else ok "$msg"; fi
  if [[ "$pending" -gt 0 ]]; then
    info "Updates are NOT applied automatically — review and apply: skills-update   (unreviewed: skills-update --yes, or SKILLS_AUTO_APPLY=1)"
  fi
  info "List: ls ~/.claude/skills   |   verify: ./02-doctor.sh   |   update: skills-update   |   sources: $SRC_DIR"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)   MODE=check ;;
      --review)  MODE=review ;;
      --yes|-y)  MODE=yes ;;
      --strict)  STRICT=1 ;;
      -h|--help) usage; exit 0 ;;
      *) err "Unknown option: $1 (try --help)"; exit 2 ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  step "Agent Skills (global -> ~/.claude/skills)"
  if ! has git; then warn "git not found — skipping skills."; exit 0; fi

  mkdir -p "$SKILLS_DIR" "$SRC_DIR"
  info "$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ') skill(s) already in ~/.claude/skills. Update mode: $MODE"

  local entry url filter dir link_jobs=""
  for entry in "${SKILL_SOURCES[@]}"; do
    url="${entry%%|*}"; filter="${entry#*|}"
    dir="$SRC_DIR/$(src_name "$url")"
    migrate_legacy "$url"
    sync_repo "$url" "$dir" "$filter"
    tally "$(basename "$dir")"
    if [[ -d "$dir/.git" ]]; then link_jobs="${link_jobs}${dir}|${filter}"$'\n'; fi
  done
  prune_dangling
  while IFS='|' read -r dir filter; do
    if [[ -n "$dir" ]]; then link_skills "$dir" "$filter"; fi
  done <<< "$link_jobs"

  local n cdir
  for entry in "${CLONE_ONLY_SOURCES[@]}"; do
    url="${entry%%|*}"; cdir="${entry#*|}"; dir="$SRC_DIR/$cdir"
    sync_repo "$url" "$dir" ""
    tally "$cdir"
    if [[ -d "$dir/.git" ]]; then
      n="$(find "$dir" -mindepth 2 -name SKILL.md -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
      ok "available (not linked): $cdir — $n skills; activate per-project with /skills-review"
    fi
  done

  summary
  exit "$(final_rc)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
