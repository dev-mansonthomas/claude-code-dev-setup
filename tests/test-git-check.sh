#!/usr/bin/env bash
# Unit tests for git-check (read-only). Sources the script, stubs the git_/gh_ seams with canned
# read output, and asserts the JSON schema + that NO mutating command is ever invoked.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"
# shellcheck source=git-check
. "$ROOT/git-check"

TESTTMP="$(mktemp -d)"; CALLS="$TESTTMP/calls.log"
trap 'rm -rf "$TESTTMP"' EXIT

now_()  { echo "2026-01-01T00:00:00Z"; }
have_() { return 0; }

STUB_OPEN='[{"number":1,"title":"a","headRefName":"feat/x","isDraft":false,"url":"u"}]'
STUB_MERGED='[{"number":2,"title":"b","headRefName":"feat/old","mergedAt":"t","url":"u"}]'

gh_() {
  echo "gh $*" >> "$CALLS"
  case "$1 ${2:-}" in
    "auth status") return 0 ;;
    "repo view")
      if printf '%s' "$*" | grep -q nameWithOwner; then echo "owner/name";
      elif printf '%s' "$*" | grep -q defaultBranchRef; then echo "main"; fi ;;
    "pr list")
      if printf '%s' "$*" | grep -q 'state open'; then printf '%s' "$STUB_OPEN";
      else printf '%s' "$STUB_MERGED"; fi ;;
    *) return 0 ;;
  esac
}
git_() {
  echo "git $*" >> "$CALLS"
  case "$1" in
    rev-parse) case "${2:-}" in --show-toplevel) echo "$TESTTMP" ;; --is-inside-work-tree) echo true ;; esac ;;
    ls-remote) printf 'abc123\trefs/heads/main\ndef456\trefs/heads/feat/old\n' ;;
    branch)    printf '  origin/feat/old\n  origin/main\n' ;;
    log)       printf 'abc1234 feat: x\ndef5678 fix: y\n' ;;
    fetch)     return 0 ;;
    *) return 0 ;;
  esac
}

: > "$CALLS"; OUT="$(main)"; CODE=$?

assert_eq "git-check -> exit 0" "$CODE" "0"
assert_jq "ok"             "$OUT" '.ok' "true"
assert_jq "repo"           "$OUT" '.repo' "owner/name"
assert_jq "base"           "$OUT" '.base' "main"
assert_jq "openPRs len"    "$OUT" '.openPRs | length' "1"
assert_jq "merged len"     "$OUT" '.recentlyMerged | length' "1"
assert_jq "remote feat/old merged" "$OUT" '[.remoteBranches[] | select(.name=="feat/old")][0].merged' "true"
assert_jq "stale has feat/old" "$OUT" '.staleBranches | contains(["feat/old"])' "true"
assert_jq "stale excludes base" "$OUT" '.staleBranches | contains(["main"])' "false"
assert_jq "mainLog len"    "$OUT" '.mainLog | length' "2"
assert_jq "mainLog sha"    "$OUT" '.mainLog[0].sha' "abc1234"
assert_eq "report file written" "$( [ -f "$TESTTMP/debug/git/git-check.json" ] && echo y )" "y"

assert_no_call "no pr create" "pr create" "$CALLS"
assert_no_call "no pr merge"  "pr merge"  "$CALLS"
assert_no_call "no push"      "git push"  "$CALLS"
assert_no_call "no branch -d" "git branch -d" "$CALLS"

# Handoff prompt goes to stderr (stdout stays pure JSON) and names the repo-relative report.
ERROUT="$( main 2>&1 >/dev/null )"
case "$ERROUT" in *"debug/git/git-check.json"*) hf=y ;; *) hf=n ;; esac
assert_eq "handoff names report path (stderr)" "$hf" "y"
case "$ERROUT" in *"Read "*"Cross-check"*) hp=y ;; *) hp=n ;; esac
assert_eq "handoff carries the prompt" "$hp" "y"
assert_jq "stdout stays pure JSON" "$OUT" '.tool' "git-check"

suite_summary "git-check"
