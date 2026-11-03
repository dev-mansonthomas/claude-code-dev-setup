#!/usr/bin/env bash
# Tests for 03-vm-up.sh's option surface: --help lists EVERY environment variable with its
# consequences, unknown options / bad values fail before anything starts, only documented variables
# are forwarded into the VM (never secrets), the end-of-run recap lists them with current values,
# and a drift guard fails when a script reads an environment variable that --help does not mention.
# Nothing here starts Colima: --help and validation exit before the first brew/colima call.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"
# shellcheck source=scripts/vm-env.sh
. "$ROOT/scripts/vm-env.sh"

contains() { printf '%s' "$1" | grep -q -- "$2"; }
yn()       { if "$@"; then echo yes; else echo no; fi; }
UP="$ROOT/03-vm-up.sh"

# A developer's own settings must not leak into the checks below.
unset SKILLS_AUTO_APPLY NO_COLOR

# --- 1. --help ---------------------------------------------------------------------------------
HELP="$(PATH=/usr/bin:/bin bash "$UP" --help 2>&1)"; CODE=$?
assert_eq "--help exits 0"                    "$CODE" "0"
assert_eq "--help has no side effects"        "$(yn contains "$HELP" 'Homebrew required')" "no"
for s in "USAGE" "WHAT IT DOES" "ENVIRONMENT VARIABLES" "NOT CONFIGURABLE" "AFTER IT RUNS"; do
  assert_eq "--help section: $s"              "$(yn contains "$HELP" "$s")" "yes"
done
NAMES=""
for rec in "${ENV_CATALOG[@]}"; do NAMES="$NAMES ${rec%%|*}"; done
for n in $NAMES; do
  assert_eq "--help lists $n"                 "$(yn contains "$HELP" "$n")" "yes"
done
# Phrases may be wrapped across lines by the help renderer: compare against the flattened text.
HELP_FLAT="$(printf '%s' "$HELP" | tr '\n' ' ' | tr -s ' ')"
assert_eq "--help explains the consequence of SKILLS_AUTO_APPLY=1" "$(yn contains "$HELP_FLAT" 'applied automatically and unreviewed')" "yes"
assert_eq "--help says AUTO_YES never approves updates"            "$(yn contains "$HELP_FLAT" 'does NOT approve skill updates')" "yes"
assert_eq "--help explains why CONTEXT7_API_KEY is not forwarded"  "$(yn contains "$HELP_FLAT" "readable with 'ps'")" "yes"

# --- 2. bad invocations fail before anything starts ----------------------------------------------
OUT="$(PATH=/usr/bin:/bin bash "$UP" --bogus 2>&1)"; CODE=$?
assert_eq "unknown option -> exit 2"          "$CODE" "2"
assert_eq "unknown option points to --help"   "$(yn contains "$OUT" '\-\-help')" "yes"
OUT="$(PATH=/usr/bin:/bin SKILLS_AUTO_APPLY=2 bash "$UP" 2>&1)"; CODE=$?
assert_eq "SKILLS_AUTO_APPLY=2 -> exit 2"     "$CODE" "2"
assert_eq "bad value is explained"            "$(yn contains "$OUT" 'must be 0 or 1')" "yes"
assert_eq "bad value stops before Colima"     "$(yn contains "$OUT" 'Colima VM')" "no"

# --- 3. forwarding into the VM: documented variables only ---------------------------------------
assert_eq "nothing set -> nothing forwarded"  "$(forwarded_env_lines)" ""
assert_eq "SKILLS_AUTO_APPLY=1 is forwarded"  "$(SKILLS_AUTO_APPLY=1 forwarded_env_lines)" "SKILLS_AUTO_APPLY=1"
assert_eq "unrelated + secret vars never forwarded" \
  "$(CONTEXT7_API_KEY=s3cret AUTO_YES=1 NO_COLOR=1 GITHUB_TOKEN=x SKILLS_AUTO_APPLY=0 forwarded_env_lines)" \
  "SKILLS_AUTO_APPLY=0"

# --- 4. end-of-run recap -------------------------------------------------------------------------
RECAP="$(render_env_recap)"
for n in $NAMES; do
  assert_eq "recap lists $n"                  "$(yn contains "$RECAP" "$n")" "yes"
done
assert_eq "recap shows default SKILLS_AUTO_APPLY=0"  "$(yn contains "$(render_env_recap | grep SKILLS_AUTO_APPLY)" 'now: 0')" "yes"
assert_eq "recap reflects the current value"         "$(yn contains "$(SKILLS_AUTO_APPLY=1 render_env_recap | grep SKILLS_AUTO_APPLY)" 'now: 1')" "yes"
assert_eq "recap is succinct (one line per variable)" "$(printf '%s\n' "$RECAP" | wc -l | tr -d ' ')" "${#ENV_CATALOG[@]}"

# --- 5. drift guard: every environment variable the scripts READ is documented in --help ---------
# A read is a ${NAME:-…} / ${NAME:=…} / ${NAME-…} / ${NAME=…} form on an UPPER_CASE name. Add a new
# knob to any of these scripts and this fails until --help mentions it.
READ_FROM="03-vm-up.sh scripts/lib.sh scripts/vm-env.sh scripts/vm-provision.sh scripts/20-skills.sh \
scripts/30-mcp.sh scripts/40-plugins.sh scripts/50-global-config.sh scripts/skill-activate.sh scripts/skills-update.sh"
# Not user-facing knobs: BACKUP_DIR is an internal default for the config step's backups.
INTERNAL=" BACKUP_DIR "
for f in $READ_FROM; do
  while IFS= read -r n; do
    case "$INTERNAL" in *" $n "*) continue ;; esac
    assert_eq "documented in --help: $n (read by $f)" "$(yn contains "$HELP" "$n")" "yes"
  done < <(grep -ohE '\$\{[A-Z][A-Z0-9_]*(:-|:=|-|=)' "$ROOT/$f" | sed -E 's/^\$\{//; s/(:-|:=|-|=)$//' | sort -u)
done

suite_summary "03-vm-up"
