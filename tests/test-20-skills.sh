#!/usr/bin/env bash
# Tests for scripts/20-skills.sh: update gating (check/review/yes), legacy-clone migration, dead-link
# pruning, survival of an upstream force-push, failure accounting, option parsing.
# Uses REAL local git repos (file://) — no network, no git stubs — inside a throwaway HOME, so
# nothing under the real ~/.claude is touched. Sourcing 20-skills.sh runs nothing (run-guard).
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"

unset SKILLS_AUTO_APPLY AUTO_YES SKILLS_SRC_DIR   # a developer's own settings must not leak into the suite
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
UP="$T/upstream"; mkdir -p "$UP"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# shellcheck source=scripts/20-skills.sh
. "$ROOT/scripts/20-skills.sh"
SRC_DIR="$T/src"; SKILLS_DIR="$T/skills"

# --- upstream fixtures ---------------------------------------------------------------------------
up_init()   { mkdir -p "$UP/$1"; git -C "$UP/$1" init -q; git -C "$UP/$1" symbolic-ref HEAD refs/heads/main; }
up_skill()  { mkdir -p "$UP/$1/$2"; printf '%s\n' "$3" > "$UP/$1/$2/SKILL.md"; }   # <repo> <dir-in-repo> <text>
up_commit() { git -C "$UP/$1" add -A; git -C "$UP/$1" commit -q -m "${2:-c}"; }
up_head()   { git -C "$UP/$1" rev-parse HEAD; }

URL="file://$UP/o/r"; DIR="$SRC_DIR/o-r"
fresh_world() { rm -rf "$SRC_DIR" "$SKILLS_DIR"; mkdir -p "$SRC_DIR" "$SKILLS_DIR"; linked=0; updated=0; pending=0; FAILED=0; }
sync_q()      { sync_repo "$1" "$2" "${3:-}" > "$T/out" 2>&1; OUT="$(cat "$T/out")"; }
clone_head()  { git -C "$DIR" rev-parse HEAD; }
yn()          { if "$@"; then echo yes; else echo no; fi; }   # yn <test…> -> yes/no, for assert_eq
contains()    { printf '%s' "$1" | grep -q -- "$2"; }          # contains <haystack> <needle>

up_init o/r
up_skill o/r skills/alpha "alpha v1"
up_skill o/r skills/beta  "beta v1"
up_commit o/r "initial"

# --- 1. fresh install: cloned and linked, no prompt ---------------------------------------------
fresh_world; MODE=check
sync_q "$URL" "$DIR"
assert_eq "fresh -> cloned"            "$SYNC" "cloned"
link_skills "$DIR" "" > /dev/null
assert_eq "fresh -> alpha linked"      "$(yn test -e "$SKILLS_DIR/alpha/SKILL.md")" "yes"
assert_eq "fresh -> beta linked"       "$(yn test -e "$SKILLS_DIR/beta/SKILL.md")"  "yes"
assert_eq "clone dir is owner-repo"    "$(yn test -d "$DIR/.git")" "yes"

# --- 2. nothing new upstream ---------------------------------------------------------------------
sync_q "$URL" "$DIR"
assert_eq "no change -> uptodate"      "$SYNC" "uptodate"

# --- 3. upstream changes, --check: reported, NOT applied ----------------------------------------
up_skill o/r skills/gamma "gamma v1"
up_skill o/r skills/alpha "alpha v2"
up_commit o/r "add gamma, change alpha"
BEFORE="$(clone_head)"
MODE=check; sync_q "$URL" "$DIR"
assert_eq "check -> pending"           "$SYNC" "pending"
assert_eq "check -> clone untouched"   "$(clone_head)" "$BEFORE"
assert_eq "check -> reports gamma"     "$(yn contains "$OUT" '+gamma')" "yes"
assert_eq "check -> reports alpha"     "$(yn contains "$OUT" '~alpha')" "yes"
link_skills "$DIR" "" > /dev/null
assert_eq "check -> gamma NOT linked"  "$(yn test -e "$SKILLS_DIR/gamma")" "no"

# --- 4. --review without a terminal falls back to check -----------------------------------------
MODE=review; is_tty() { return 1; }
sync_q "$URL" "$DIR"
assert_eq "review, no tty -> pending"  "$SYNC" "pending"
assert_eq "review, no tty -> warns"    "$(yn contains "$OUT" 'needs a terminal')" "yes"
assert_eq "review, no tty -> untouched" "$(clone_head)" "$BEFORE"

# --- 5. --review, user declines ------------------------------------------------------------------
is_tty() { return 0; }; confirm_apply() { return 1; }
sync_q "$URL" "$DIR"
assert_eq "review, declined"           "$SYNC" "declined"
assert_eq "review shows the diff"      "$(yn contains "$OUT" 'full diff: git -C')" "yes"
assert_eq "review shows added skill"   "$(yn contains "$OUT" '+gamma')" "yes"
assert_eq "declined -> untouched"      "$(clone_head)" "$BEFORE"
assert_eq "declined -> not linked"     "$(yn test -e "$SKILLS_DIR/gamma")" "no"

# --- 6. --review, user accepts -------------------------------------------------------------------
confirm_apply() { return 0; }
sync_q "$URL" "$DIR"
assert_eq "review, accepted"           "$SYNC" "updated"
assert_eq "accepted -> clone at upstream" "$(clone_head)" "$(up_head o/r)"
link_skills "$DIR" "" > /dev/null
assert_eq "accepted -> gamma linked"   "$(yn test -e "$SKILLS_DIR/gamma/SKILL.md")" "yes"
assert_eq "accepted -> alpha updated"  "$(cat "$DIR/skills/alpha/SKILL.md")" "alpha v2"

# --- 7. --yes applies without asking -------------------------------------------------------------
up_skill o/r skills/delta "delta v1"; up_commit o/r "add delta"
confirm_apply() { echo "confirm_apply must not be called in yes mode" >&2; return 1; }
MODE=yes; sync_q "$URL" "$DIR"
assert_eq "yes -> updated"             "$SYNC" "updated"
assert_eq "yes -> at upstream"         "$(clone_head)" "$(up_head o/r)"

# --- 8. upstream force-push (history rewritten) still applies ------------------------------------
up_skill o/r skills/alpha "alpha v3 (rewritten)"
git -C "$UP/o/r" add -A; git -C "$UP/o/r" commit -q --amend -m "rewritten tip"
sync_q "$URL" "$DIR"
assert_eq "force-push -> updated"      "$SYNC" "updated"
assert_eq "force-push -> content"      "$(cat "$DIR/skills/alpha/SKILL.md")" "alpha v3 (rewritten)"

# --- 9. a skill moved upstream: dead link pruned, re-linked at its new path ---------------------
link_skills "$DIR" "" > /dev/null
OLD_TARGET="$(readlink "$SKILLS_DIR/alpha")"
git -C "$UP/o/r" mv skills/alpha alpha; up_commit o/r "move alpha"
MODE=yes; sync_q "$URL" "$DIR"
assert_eq "moved -> link now dangling" "$(yn test -e "$SKILLS_DIR/alpha")" "no"
prune_dangling > /dev/null 2>&1
assert_eq "moved -> dead link pruned"  "$(yn test -L "$SKILLS_DIR/alpha")" "no"
link_skills "$DIR" "" > /dev/null
assert_eq "moved -> re-linked, valid"  "$(yn test -e "$SKILLS_DIR/alpha/SKILL.md")" "yes"
assert_eq "moved -> new target path"   "$(yn test "$(readlink "$SKILLS_DIR/alpha")" != "$OLD_TARGET")" "yes"

# --- 10. filter: only allowlisted skills are linked / reported -----------------------------------
fresh_world; MODE=check
sync_q "$URL" "$DIR" "beta"
link_skills "$DIR" "beta" > /dev/null
assert_eq "filter -> beta linked"      "$(yn test -e "$SKILLS_DIR/beta")" "yes"
assert_eq "filter -> others skipped"   "$(yn test -e "$SKILLS_DIR/gamma")" "no"
up_skill o/r unlisted "unlisted v1"; up_commit o/r "add unlisted"
sync_q "$URL" "$DIR" "beta"
assert_eq "filter -> unlisted not reported" "$(yn contains "$OUT" '+unlisted')" "no"

# --- 11. legacy clone (bare repo name) is adopted, links re-pointed ------------------------------
fresh_world
git clone -q --depth 1 "$URL" "$SRC_DIR/r"
ln -s "$SRC_DIR/r/skills/beta" "$SKILLS_DIR/beta"
migrate_legacy "$URL" > /dev/null 2>&1
assert_eq "legacy -> renamed"          "$(yn test -d "$DIR/.git")" "yes"
assert_eq "legacy -> old dir gone"     "$(yn test -e "$SRC_DIR/r")" "no"
assert_eq "legacy -> link still valid" "$(yn test -e "$SKILLS_DIR/beta/SKILL.md")" "yes"
assert_eq "legacy -> link re-pointed"  "$(yn contains "$(readlink "$SKILLS_DIR/beta")" "$SRC_DIR/o-r/")" "yes"
MODE=check; sync_q "$URL" "$DIR"
assert_eq "legacy -> now refreshed"    "$SYNC" "uptodate"   # the adopted clone is a normal, syncable one

# --- 12. a DIFFERENT repo owning the bare name is left alone -------------------------------------
fresh_world
up_init other/r; up_skill other/r skills/x "x"; up_commit other/r
git clone -q --depth 1 "file://$UP/other/r" "$SRC_DIR/r"
migrate_legacy "$URL" > /dev/null 2>&1
assert_eq "foreign repo -> untouched"  "$(yn test -d "$SRC_DIR/r/.git")" "yes"
assert_eq "foreign repo -> no o-r"     "$(yn test -e "$DIR")" "no"

# --- 13. both legacy and new exist: warn, re-point, keep the old dir -----------------------------
fresh_world
git clone -q --depth 1 "$URL" "$SRC_DIR/r"; git clone -q --depth 1 "$URL" "$DIR"
ln -s "$SRC_DIR/r/skills/beta" "$SKILLS_DIR/beta"
OUT="$(migrate_legacy "$URL" 2>&1)"
assert_eq "duplicate -> warned"        "$(yn contains "$OUT" 'duplicates')" "yes"
assert_eq "duplicate -> old kept"      "$(yn test -d "$SRC_DIR/r/.git")" "yes"
assert_eq "duplicate -> link moved"    "$(yn contains "$(readlink "$SKILLS_DIR/beta")" "$SRC_DIR/o-r/")" "yes"

# --- 14. failures: unreachable source, vanished remote; strict exit code -------------------------
fresh_world
sync_q "file://$UP/nope/none" "$SRC_DIR/nope-none"
assert_eq "bad url -> failed"          "$SYNC" "failed"
tally nope-none > /dev/null 2>&1
assert_eq "failure counted"            "$FAILED" "1"
STRICT=0; assert_eq "non-strict rc stays 0" "$(final_rc)" "0"
STRICT=1; assert_eq "strict rc is 1"        "$(final_rc)" "1"
FAILED=0; assert_eq "strict, no failure -> 0" "$(final_rc)" "0"; STRICT=0
fresh_world; MODE=check; sync_q "$URL" "$DIR"; BEFORE="$(clone_head)"
mv "$UP/o/r" "$UP/o/r.gone"
sync_q "$URL" "$DIR"
assert_eq "remote vanished -> failed"  "$SYNC" "failed"
assert_eq "remote vanished -> clone kept" "$(clone_head)" "$BEFORE"
mv "$UP/o/r.gone" "$UP/o/r"

# --- 15. naming ------------------------------------------------------------------------------------
assert_eq "src_name anthropics"   "$(src_name https://github.com/anthropics/skills)"         "anthropics-skills"
assert_eq "src_name vercel skills" "$(src_name https://github.com/vercel-labs/skills.git)"   "vercel-labs-skills"
assert_eq "src_name file://"      "$(src_name "file://$UP/o/r")"                              "o-r"

# --- 16. option parsing & environment (separate processes) ---------------------------------------
SCRIPT="$ROOT/scripts/20-skills.sh"
HELP="$(bash "$SCRIPT" --help 2>&1)"; CODE=$?
assert_eq "--help exits 0"             "$CODE" "0"
assert_eq "--help documents SKILLS_AUTO_APPLY" "$(yn contains "$HELP" 'SKILLS_AUTO_APPLY')" "yes"
assert_eq "--help says AUTO_YES does not approve" "$(yn contains "$HELP" 'does NOT approve')" "yes"
assert_eq "--help documents --strict"  "$(yn contains "$HELP" '\-\-strict')" "yes"
bash "$SCRIPT" --bogus > /dev/null 2>&1; assert_eq "unknown option -> exit 2" "$?" "2"
assert_eq "default mode is check"      "$(bash -c ". '$SCRIPT'; printf %s \"\$MODE\"" 2>/dev/null)" "check"
assert_eq "AUTO_YES=1 does NOT approve updates" "$(AUTO_YES=1 bash -c ". '$SCRIPT'; printf %s \"\$MODE\"" 2>/dev/null)" "check"
assert_eq "SKILLS_AUTO_APPLY=1 -> yes" "$(SKILLS_AUTO_APPLY=1 bash -c ". '$SCRIPT'; printf %s \"\$MODE\"" 2>/dev/null)" "yes"

# --- 17. skills-update wrapper: own help, resolves through a PATH symlink ------------------------
ln -s "$ROOT/scripts/skills-update.sh" "$T/skills-update"
SUHELP="$("$T/skills-update" --help 2>&1)"; CODE=$?
assert_eq "skills-update --help exits 0" "$CODE" "0"
assert_eq "skills-update has its own help" "$(yn contains "$SUHELP" 'Exit status')" "yes"
"$T/skills-update" --bogus > /dev/null 2>&1; assert_eq "skills-update bad option -> 2" "$?" "2"

suite_summary "20-skills"
