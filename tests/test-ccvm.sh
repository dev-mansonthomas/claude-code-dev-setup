#!/usr/bin/env bash
# Tests for ccvm: -h/--help works without Colima and documents every option + environment variable,
# and the documented behaviour (permission mode switches, argument forwarding and refusal, ~/Projects
# guard) is what the script actually does. A fake `colima` on PATH records the command that would run
# in the VM, so no VM is needed. HOME is a throwaway directory.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"

contains() { printf '%s' "$1" | grep -q -- "$2"; }
yn()       { if "$@"; then echo yes; else echo no; fi; }
unset CCVM_SAFE CCVM_YOLO CLAUDE_CODE_OAUTH_TOKEN CC_TOKEN_FILE

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/Projects/app" "$T/bin" "$T/elsewhere"
cat > "$T/bin/colima" <<'EOF'
#!/bin/bash
case "$1" in
  status) exit 0 ;;
  ssh)    shift; [ "$1" = "--" ] && shift; printf '%s\n' "$*" >> "$FAKE_LOG"; exit 0 ;;
esac
EOF
chmod +x "$T/bin/colima"
CCVM="$ROOT/ccvm"
# run_ccvm <args...> — with the fake colima, no `code`, throwaway HOME; sets OUT, CODE, CMD (last VM command)
run_ccvm() {
  : > "$T/log"
  OUT="$(HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" FAKE_LOG="$T/log" bash "$CCVM" "$@" 2>&1)"; CODE=$?
  CMD="$(tail -1 "$T/log")"
}

# --- 1. help: both spellings, no Colima needed -------------------------------------------------
for flag in -h --help; do
  HELP="$(HOME="$T/home" PATH=/usr/bin:/bin bash "$CCVM" "$flag" 2>&1)"; CODE=$?
  assert_eq "$flag exits 0 without colima"   "$CODE" "0"
  assert_eq "$flag prints the help"          "$(yn contains "$HELP" 'USAGE')" "yes"
done
for s in "USAGE" "<project>" "claude-args" "WHAT A SESSION DOES" "PERMISSION MODE" \
         "ENVIRONMENT VARIABLES" "EXIT STATUS" "EXAMPLES" "--worktree"; do
  assert_eq "help covers: $s"                "$(yn contains "$HELP" "$s")" "yes"
done
# Drift guard: every ${VAR:-…} the script reads must be documented in the help.
while IFS= read -r n; do
  assert_eq "help documents $n"              "$(yn contains "$HELP" "$n")" "yes"
done < <(grep -ohE '\$\{[A-Z][A-Z0-9_]*(:-|:=|-|=)' "$CCVM" | sed -E 's/^\$\{//; s/(:-|:=|-|=)$//' | sort -u)

# --- 2. permission mode switches behave as documented ------------------------------------------
run_ccvm app
assert_eq "default -> auto"                  "$(yn contains "$CMD" 'claude --permission-mode auto')" "yes"
CCVM_SAFE=1 run_ccvm app
assert_eq "CCVM_SAFE=1 -> acceptEdits"       "$(yn contains "$CMD" '--permission-mode acceptEdits')" "yes"
CCVM_SAFE=0 run_ccvm app
assert_eq "CCVM_SAFE=0 -> off (auto)"        "$(yn contains "$CMD" '--permission-mode auto')" "yes"
CCVM_SAFE=1 CCVM_YOLO=1 run_ccvm app
assert_eq "CCVM_YOLO wins over CCVM_SAFE"    "$(yn contains "$CMD" '--dangerously-skip-permissions')" "yes"
CCVM_YOLO=0 run_ccvm app
assert_eq "CCVM_YOLO=0 -> off (auto)"        "$(yn contains "$CMD" '--permission-mode auto')" "yes"

# --- 3. arguments --------------------------------------------------------------------------------
run_ccvm app --worktree gps-live
assert_eq "safe args are forwarded"          "$(yn contains "$CMD" 'auto --worktree gps-live')" "yes"
run_ccvm app --help
assert_eq "<project> --help goes to claude"  "$(yn contains "$CMD" 'auto --help')" "yes"
run_ccvm app 'x y'
assert_eq "arg with a space -> exit 2"       "$CODE" "2"
assert_eq "refused arg never reaches the VM" "$CMD" ""
# shellcheck disable=SC2016  # the literal $(id) is the point: it must be refused, never expanded
run_ccvm app '$(id)'
assert_eq "shell metachar -> exit 2"         "$CODE" "2"
run_ccvm nope
assert_eq "unknown project -> exit 1"        "$CODE" "1"
run_ccvm "$T/elsewhere"
assert_eq "outside ~/Projects -> exit 1"     "$CODE" "1"
assert_eq "outside ~/Projects is explained"  "$(yn contains "$OUT" "isn't mounted")" "yes"

# --- 4. the token never appears on the VM command line -------------------------------------------
CLAUDE_CODE_OAUTH_TOKEN=sk-secret-123 run_ccvm app
assert_eq "token not in the VM command"      "$(yn contains "$(cat "$T/log")" 'sk-secret-123')" "no"

suite_summary "ccvm"
