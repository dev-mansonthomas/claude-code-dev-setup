#!/usr/bin/env bash
# Tiny assert helpers for the host-git-utilities suite (bash 3.2-safe, no framework).
TESTS_RUN=0; TESTS_FAIL=0
_pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
_fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; TESTS_FAIL=$((TESTS_FAIL + 1)); }

assert_eq() {   # assert_eq <desc> <got> <expected>
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1 — got '$2', expected '$3'"; fi
}
assert_jq() {   # assert_jq <desc> <json> <jq-filter> <expected>
  local got
  got="$(printf '%s' "$2" | jq -r "$3" 2>/dev/null)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$got" = "$4" ]; then _pass "$1 [$3=$4]"; else _fail "$1 — jq '$3' = '$got', expected '$4'"; fi
}
assert_call() {   # assert_call <desc> <substring> <calls-file>
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q -- "$2" "$3"; then _pass "$1 [called: $2]"; else _fail "$1 — expected call '$2'"; fi
}
assert_no_call() {   # assert_no_call <desc> <substring> <calls-file>
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q -- "$2" "$3"; then _fail "$1 — unexpected call '$2'"; else _pass "$1 [not called: $2]"; fi
}
suite_summary() {   # suite_summary <name>
  printf '\n%s: %d run, %d failed\n' "$1" "$TESTS_RUN" "$TESTS_FAIL"
  [ "$TESTS_FAIL" = 0 ]
}
