#!/usr/bin/env bash
# Unit tests for git-pr-merge. Sources the script (the run-guard doesn't fire when sourced), then
# overrides the git_/gh_/now_/have_/sleep_ seams with stubs and runs main in a subshell ($(...)),
# so `exit` only exits the subshell and no real git/GitHub call is made.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"
# shellcheck source=git-pr-merge
. "$ROOT/git-pr-merge"

TESTTMP="$(mktemp -d)"; CALLS="$TESTTMP/calls.log"
trap 'rm -rf "$TESTTMP"' EXIT

# --- stubs -----------------------------------------------------------------
now_()   { echo "2026-01-01T00:00:00Z"; }
sleep_() { :; }
have_()  { case "$1" in "${STUB_MISSING:-__none__}") return 1 ;; *) return 0 ;; esac; }

git_() {
  echo "git $*" >> "$CALLS"
  case "$1" in
    rev-parse)
      case "${2:-}" in
        --show-toplevel)        echo "$TESTTMP" ;;
        --is-inside-work-tree)  if [ "${STUB_IN_REPO:-1}" = 1 ]; then echo true; else return 1; fi ;;
        --abbrev-ref)           echo "${STUB_CUR_BRANCH:-feat/x}" ;;
      esac ;;
    rev-list)  echo "${STUB_AHEAD:-1}" ;;
    status)    printf '%s' "${STUB_DIRTY:-}" ;;
    push)      [ "${STUB_PUSH_OK:-1}" = 1 ] ;;
    checkout|pull|fetch) return 0 ;;
    branch)    return 0 ;;
    show-ref)  return 1 ;;   # branch absent after merge (gh --delete-branch removed it)
    *) return 0 ;;
  esac
}

gh_() {
  echo "gh $*" >> "$CALLS"
  case "$1 ${2:-}" in
    "auth status") [ "${STUB_AUTHED:-1}" = 1 ] ;;
    "repo view")
      if printf '%s' "$*" | grep -q nameWithOwner; then echo "${STUB_REPO:-owner/name}";
      elif printf '%s' "$*" | grep -q defaultBranchRef; then echo "${STUB_DEFAULT_BRANCH:-main}"; fi ;;
    "pr view")
      if printf '%s' "$*" | grep -q mergeCommit; then echo "${STUB_MERGE_SHA:-abc1234def}";
      elif printf '%s' "$*" | grep -q -- '-q'; then echo "${STUB_PR_NUMBER:-14}";
      else
        if [ -z "${STUB_PR_VIEW_STATE:-}" ]; then return 1; fi
        printf '{"number":%s,"state":"%s","url":"%s"}\n' \
          "${STUB_PR_NUMBER:-14}" "$STUB_PR_VIEW_STATE" "${STUB_PR_URL:-https://gh/o/r/pull/14}"
      fi ;;
    "pr create") if [ "${STUB_CREATE_OK:-1}" = 1 ]; then echo "${STUB_PR_URL:-https://gh/o/r/pull/14}"; else return 1; fi ;;
    "pr checks") case "${STUB_CHECKS:-NONE}" in NONE) return 1 ;; *) printf '%s' "$STUB_CHECKS" ;; esac ;;
    "pr merge") [ "${STUB_MERGE_OK:-1}" = 1 ] ;;
    *) return 0 ;;
  esac
}

reset_stubs() {
  unset STUB_MISSING STUB_IN_REPO STUB_AUTHED STUB_CUR_BRANCH STUB_AHEAD STUB_DIRTY \
        STUB_PR_VIEW_STATE STUB_PR_NUMBER STUB_PR_URL STUB_PUSH_OK STUB_CREATE_OK \
        STUB_CHECKS STUB_MERGE_OK STUB_MERGE_SHA STUB_REPO STUB_DEFAULT_BRANCH
}
run() { : > "$CALLS"; OUT="$(main "$@")"; CODE=$?; }

# --- scenarios -------------------------------------------------------------
reset_stubs; STUB_MISSING=gh; run "t"
assert_jq   "missing gh -> preconditions" "$OUT" '.error.code' "preconditions"
assert_eq   "missing gh -> exit 3" "$CODE" "3"

reset_stubs; STUB_IN_REPO=0; run "t"
assert_eq   "not a repo -> exit 3" "$CODE" "3"

reset_stubs; STUB_AUTHED=0; run "t"
assert_jq   "gh not authed -> preconditions" "$OUT" '.error.code' "preconditions"
assert_eq   "gh not authed -> exit 3" "$CODE" "3"

reset_stubs; STUB_CUR_BRANCH=main; run "t"
assert_jq   "on base -> usage" "$OUT" '.error.code' "usage"
assert_eq   "on base -> exit 2" "$CODE" "2"
assert_no_call "on base -> no push" "git push" "$CALLS"

reset_stubs; STUB_AHEAD=0; run "t"
assert_eq   "no commits ahead -> exit 2" "$CODE" "2"

reset_stubs; STUB_CHECKS='[{"bucket":"pass","name":"shellcheck","state":"SUCCESS","link":"x"}]'; run "Title" "Body"
assert_eq   "happy -> exit 0" "$CODE" "0"
assert_jq   "happy -> ok" "$OUT" '.ok' "true"
assert_jq   "happy -> ci success" "$OUT" '.ci' "success"
assert_jq   "happy -> pr.number" "$OUT" '.pr.number' "14"
assert_jq   "happy -> merged" "$OUT" '.merged' "true"
assert_jq   "happy -> mergedSha" "$OUT" '.mergedSha' "abc1234"
assert_jq   "happy -> reportPath" "$OUT" '.reportPath' "debug/git/git-pr-merge.json"
assert_jq   "happy -> local branch pruned" "$OUT" '.branchDeleted.local' "true"
assert_call "happy -> created PR" "pr create" "$CALLS"
assert_call "happy -> merged PR" "pr merge" "$CALLS"

reset_stubs; STUB_PR_VIEW_STATE=OPEN; STUB_CHECKS='[{"bucket":"pass","name":"x","state":"SUCCESS","link":"x"}]'; run "t"
assert_jq   "reuse -> pr.reused" "$OUT" '.pr.reused' "true"
assert_no_call "reuse -> no pr create" "pr create" "$CALLS"

reset_stubs; STUB_PR_VIEW_STATE=MERGED; run "t"
assert_jq   "already merged -> alreadyMerged" "$OUT" '.alreadyMerged' "true"
assert_eq   "already merged -> exit 0" "$CODE" "0"
assert_no_call "already merged -> no pr merge" "pr merge" "$CALLS"

reset_stubs; STUB_CHECKS=NONE; run "t"
assert_jq   "no checks -> ci none" "$OUT" '.ci' "none"
assert_call "no checks -> still merges" "pr merge" "$CALLS"

reset_stubs; STUB_CHECKS='[{"bucket":"fail","name":"lint","state":"FAILURE","link":"https://gh/o/r/actions/runs/123/job/9"}]'; run "t"
assert_jq   "ci fail -> ci failed" "$OUT" '.ci' "failed"
assert_eq   "ci fail -> exit 5" "$CODE" "5"
assert_jq   "ci fail -> 1 failing check" "$OUT" '.failingChecks | length' "1"
assert_jq   "ci fail -> logsCmd has run id" "$OUT" '.logsCmd' "gh run view 123 --log-failed"
assert_no_call "ci fail -> no merge" "pr merge" "$CALLS"

reset_stubs; STUB_CHECKS='[{"bucket":"pending","name":"x","state":"PENDING","link":"x"}]'; run --timeout 1 --poll 1 "t"
assert_jq   "ci timeout -> ci timeout" "$OUT" '.ci' "timeout"
assert_eq   "ci timeout -> exit 5" "$CODE" "5"
assert_no_call "ci timeout -> no merge" "pr merge" "$CALLS"

reset_stubs; STUB_PUSH_OK=0; run "t"
assert_jq   "push rejected -> push" "$OUT" '.error.code' "push"
assert_eq   "push rejected -> exit 4" "$CODE" "4"
assert_no_call "push rejected -> no merge" "pr merge" "$CALLS"

reset_stubs; STUB_MERGE_OK=0; STUB_CHECKS='[{"bucket":"pass","name":"x","state":"SUCCESS","link":"x"}]'; run "t"
assert_jq   "merge blocked -> merge" "$OUT" '.error.code' "merge"
assert_eq   "merge blocked -> exit 6" "$CODE" "6"

reset_stubs; STUB_CHECKS='[{"bucket":"pass","name":"x","state":"SUCCESS","link":"x"}]'; run "t"
assert_eq   "report file written" "$( [ -f "$TESTTMP/debug/git/git-pr-merge.json" ] && echo y )" "y"
assert_eq   "gitignore written"   "$( [ -f "$TESTTMP/debug/git/.gitignore" ] && echo y )" "y"

reset_stubs; STUB_CHECKS='[{"bucket":"pass","name":"x","state":"SUCCESS","link":"x"}]'; run --no-stdout "t"
assert_eq   "--no-stdout -> empty stdout" "$OUT" ""

suite_summary "git-pr-merge"
