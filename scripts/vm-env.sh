#!/usr/bin/env bash
# vm-env.sh — the environment variables that influence `./03-vm-up.sh`, documented ONCE.
# Sourced by 03-vm-up.sh (for --help, the end-of-run recap and the forwarding into the VM) and by
# tests/test-03-vm-up.sh, which FAILS when a variable is read or forwarded but not listed here.
# Needs lib.sh sourced first (err). Not meant to be executed directly.
#
# Record: NAME|DEFAULT|WHERE|SHORT|DETAIL        (no '|' inside a field; keep it ASCII - it is wrapped)
#   SHORT   one line: what the values do (shown in the end-of-run recap)
#   DETAIL  the consequences in full (shown by --help)
#   WHERE   vm   forwarded into the VM provisioning. ONLY variables listed here with WHERE=vm are
#                forwarded - never the rest of your environment, never secrets.
#           host read by 03-vm-up.sh itself, on the Mac.
#           note listed because it is commonly assumed to matter; it has NO effect on 03-vm-up.sh.
ENV_CATALOG=(
  "SKILLS_AUTO_APPLY|0|vm|1 = apply skill updates unreviewed; 0 = only report them (review with 'skills-update')|0: provisioning only FETCHES and REPORTS which skill sources have updates waiting; nothing is applied until you run 'skills-update' in the VM and approve each source. 1: every update is applied automatically and unreviewed - skills are third-party and unpinned, and a skill is instructions Claude follows (it may bundle scripts) the moment it is linked, so 1 lets upstream content change your sessions without your review. Only 0 or 1 are accepted. The first install of a source is always applied."
  "NO_COLOR|unset|host|non-empty = plain output, no colours|Any non-empty value turns colours off in this script's output (they are also off when stdout is not a terminal)."
  "HOMEBREW_NO_ENV_HINTS|1|host|0 = show Homebrew hint blocks|1 hides Homebrew's hint blocks during the colima/docker installs. Set 0 to see them."
  "HOMEBREW_NO_AUTO_UPDATE|1|host|0 = refresh brew's index before each install (slower)|1 skips the automatic 'brew update' before each install: faster, but a formula released since your last 'brew update' is not seen. Set 0 to refresh first."
  "AUTO_YES|n/a|note|no effect here; never approves skill updates|03-vm-up.sh never prompts, and provisioning already forces AUTO_YES=1 for its sub-steps, so setting it changes nothing. It does NOT approve skill updates - only SKILLS_AUTO_APPLY=1 does."
)

env_where_label() {
  case "$1" in
    vm)   printf 'forwarded to the VM provisioning' ;;
    host) printf 'read on the Mac' ;;
    *)    printf 'no effect on this script' ;;
  esac
}

# Full reference (used by --help): one block per variable, consequences wrapped.
render_env_help() {
  local rec name def where short detail
  for rec in "${ENV_CATALOG[@]}"; do
    IFS='|' read -r name def where short detail <<< "$rec"
    printf '  %s   (default: %s; %s)\n' "$name" "$def" "$(env_where_label "$where")"
    printf '%s\n' "$short" | fold -s -w 72 | sed 's/ *$//; s/^/      /'
    printf 'Consequences: %s\n' "$detail" | fold -s -w 72 | sed 's/ *$//; s/^/      /'
    printf '\n'
  done
}

# Succinct recap (used at the end of a run): one line per variable with the value now in effect.
render_env_recap() {
  local rec name def where short detail cur
  for rec in "${ENV_CATALOG[@]}"; do
    IFS='|' read -r name def where short detail <<< "$rec"
    if [[ "$where" == note ]]; then
      cur="n/a"
    else
      cur="${!name:-}"
      if [[ -z "$cur" ]]; then cur="$def"; fi
    fi
    printf '    %-24s now: %-8s %s\n' "$name" "$cur" "$short"
  done
}

# "NAME=value" for each documented WHERE=vm variable that is set and non-empty. This is the ONLY
# route by which host environment reaches the VM.
forwarded_env_lines() {
  local rec name where val
  for rec in "${ENV_CATALOG[@]}"; do
    IFS='|' read -r name _ where _ <<< "$rec"
    if [[ "$where" == vm ]]; then
      val="${!name:-}"
      if [[ -n "$val" ]]; then printf '%s=%s\n' "$name" "$val"; fi
    fi
  done
}

# Reject values the VM side would misread, before anything is started. Returns 1 after printing why.
validate_env() {
  case "${SKILLS_AUTO_APPLY:-}" in
    ""|0|1) ;;
    *) err "SKILLS_AUTO_APPLY must be 0 or 1 (got: ${SKILLS_AUTO_APPLY})"; return 1 ;;
  esac
  return 0
}
