#!/usr/bin/env bash
# git-secret-guard.sh — Claude Code PreToolUse(Bash) hook.
#
# Purpose: stop the agent from committing or pushing secrets. It only reacts to
# `git commit` / `git push` commands; everything else passes through untouched.
#
# Decision is based on gitleaks' JSON *report* (a findings array), not on exit
# codes — that keeps it stable across gitleaks versions. If gitleaks isn't
# installed, the hook FAILS OPEN (warns, allows) so it never bricks your git.
#
# Hook contract:
#   stdin  : JSON with .tool_input.command (the bash command about to run)
#   exit 0 : allow
#   exit 2 : BLOCK; stderr is shown to the agent and the user
#
# Wired up in ~/.claude/settings.json under hooks.PreToolUse (matcher "Bash").

set -uo pipefail

# --- read the command the agent is about to run ----------------------------
payload="$(cat 2>/dev/null || true)"
extract_cmd() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null
  else
    # crude fallback: pull the first "command":"..." value
    printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1
  fi
}
CMD="$(extract_cmd)"
[[ -z "$CMD" ]] && exit 0   # not a tool call we understand → allow

# --- only care about git commit / git push --------------------------------
is_commit=0; is_push=0
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)'; then is_commit=1; fi
if printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?push([[:space:]]|$)';   then is_push=1; fi
[[ $is_commit -eq 0 && $is_push -eq 0 ]] && exit 0

# --- need gitleaks; fail open if absent ------------------------------------
if ! command -v gitleaks >/dev/null 2>&1; then
  printf '⚠ git-secret-guard: gitleaks not installed — skipping scan (brew install gitleaks).\n' >&2
  exit 0
fi
# must be inside a work tree
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

REDACT="--redact --no-banner"
report="$(mktemp -t gitleaks-report.XXXXXX.json)"
trap 'rm -f "$report"; [[ -n "${scan_dir:-}" ]] && rm -rf "$scan_dir"' EXIT

findings_count() { # echo number of findings in the json report ([] when clean)
  if command -v jq >/dev/null 2>&1; then jq 'length' "$report" 2>/dev/null || echo 0
  else [[ -s "$report" ]] && grep -q '"RuleID"\|"Secret"' "$report" && echo 1 || echo 0; fi
}

# directory scan that works on modern (gitleaks dir) and older (detect) builds
scan_dir_cmd() {
  local dir="$1"
  if gitleaks dir --help >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    gitleaks dir "$dir" $REDACT --report-format json --report-path "$report" >/dev/null 2>&1 || true
  else
    # shellcheck disable=SC2086
    gitleaks detect --no-git --source "$dir" $REDACT --report-format json --report-path "$report" >/dev/null 2>&1 || true
  fi
}

block() {
  local what="$1" n="$2"
  {
    printf '\n⛔ git-secret-guard BLOCKED this %s — gitleaks found %s potential secret(s).\n\n' "$what" "$n"
    printf '   Findings (redacted):\n'
    if command -v jq >/dev/null 2>&1; then
      jq -r '.[] | "     • \(.RuleID) in \(.File):\(.StartLine)"' "$report" 2>/dev/null | head -20
    fi
    printf '\n   Fix before retrying:\n'
    printf '     - remove the secret from the staged content (use an env var / .env, and .gitignore it)\n'
    printf '     - if it is a false positive, add an allow rule to .gitleaks.toml\n\n'
  } >&2
  exit 2
}

if [[ $is_commit -eq 1 ]]; then
  scan_dir="$(mktemp -d -t gitleaks-staged.XXXXXX)"
  # staged additions/changes
  while IFS= read -r -d '' f; do
    mkdir -p "$scan_dir/$(dirname "$f")"
    git show ":$f" > "$scan_dir/$f" 2>/dev/null || true
  done < <(git diff --cached --name-only --diff-filter=ACM -z 2>/dev/null)
  # `git commit -a/--all` also commits modified *tracked* files not yet staged
  if printf '%s' "$CMD" | grep -Eq 'commit[^;&|]*(-a|--all)'; then
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      mkdir -p "$scan_dir/$(dirname "$f")"
      cp "$f" "$scan_dir/$f" 2>/dev/null || true
    done < <(git diff --name-only --diff-filter=ACM -z 2>/dev/null)
  fi
  # nothing to scan → allow
  [[ -z "$(find "$scan_dir" -type f -print -quit 2>/dev/null)" ]] && exit 0
  scan_dir_cmd "$scan_dir"
  n="$(findings_count)"
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && block "commit" "$n"
  exit 0
fi

if [[ $is_push -eq 1 ]]; then
  # best-effort: scan commits not yet on the upstream branch
  range=""
  if up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    range="${up}..HEAD"
  fi
  [[ -z "$range" ]] && { printf '⚠ git-secret-guard: no upstream to diff against — skipping push scan.\n' >&2; exit 0; }
  if gitleaks git --help >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    gitleaks git . --log-opts="$range" $REDACT --report-format json --report-path "$report" >/dev/null 2>&1 || true
  else
    # shellcheck disable=SC2086
    gitleaks detect --log-opts="$range" $REDACT --report-format json --report-path "$report" >/dev/null 2>&1 || true
  fi
  n="$(findings_count)"
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && block "push" "$n"
  exit 0
fi

exit 0
