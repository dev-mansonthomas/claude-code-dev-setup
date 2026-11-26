#!/usr/bin/env bash
# Tests for scripts/vm-clean.sh's pruners: old Claude binaries, stale Playwright revisions and
# abandoned Chromium temp profiles. Everything runs in a throwaway directory with a fake `npm`
# (for `npm root -g`); sourcing vm-clean.sh runs nothing (run-guard), so no real cache is touched.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/lib-test.sh
. "$HERE/lib-test.sh"

yn() { if "$@"; then echo yes; else echo no; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # resolved, so readlink -f results compare equal
export HOME="$T/home"; mkdir -p "$HOME" "$T/bin"
export CLAUDE_VERSIONS_DIR="$T/versions" PW_CACHE_DIR="$T/pw" CHROMIUM_PROFILE_DIR="$T/chromium"
# shellcheck source=scripts/vm-clean.sh
. "$ROOT/scripts/vm-clean.sh"

# --- 1. Claude versions: keep current + in-use, drop the rest (incl. a 0-byte failed update) ---
mkdir -p "$CLAUDE_VERSIONS_DIR"
for v in 2.1.3 2.1.31 2.1.314 2.1.331; do echo bin > "$CLAUDE_VERSIONS_DIR/$v"; done
: > "$CLAUDE_VERSIONS_DIR/2.1.332"
claude_in_use() { printf '%s\n' "$CLAUDE_VERSIONS_DIR/2.1.331" "$CLAUDE_VERSIONS_DIR/2.1.31"; }
prune_claude_versions > /dev/null
assert_eq "current version kept"          "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.331")" "yes"
assert_eq "in-use version kept"           "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.31")"  "yes"
assert_eq "prefix of in-use is not kept"  "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.3")"   "no"
assert_eq "unused version removed"        "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.314")" "no"
assert_eq "0-byte failed update removed"  "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.332")" "no"
echo bin > "$CLAUDE_VERSIONS_DIR/2.1.400"
claude_in_use() { :; }
OUT="$(prune_claude_versions)"
assert_eq "nothing resolved -> nothing removed" "$(yn test -e "$CLAUDE_VERSIONS_DIR/2.1.400")" "yes"
assert_eq "nothing resolved -> says skipped"    "$(yn grep -q skipped <<<"$OUT")" "yes"

# --- 2. Playwright: drop other revisions of the browsers the pinned version wants -------------
cat > "$T/bin/npm" <<EOF
#!/bin/sh
[ "\$1 \$2" = "root -g" ] && echo "$T/npmroot"
EOF
chmod +x "$T/bin/npm"; PATH="$T/bin:$PATH"
mkdir -p "$PW_CACHE_DIR"/{chromium-1228,chromium-1244,chromium_headless_shell-1228,chromium_headless_shell-1244,firefox-1532,firefox-1544,android-9,.links}
OUT="$(prune_playwright)"
assert_eq "no pinned playwright -> skipped"     "$(yn test -d "$PW_CACHE_DIR/chromium-1228")" "yes"
assert_eq "no pinned playwright -> says so"     "$(yn grep -q skipped <<<"$OUT")" "yes"
mkdir -p "$T/npmroot/playwright/node_modules/playwright-core"
cat > "$T/npmroot/playwright/node_modules/playwright-core/browsers.json" <<'EOF'
{"browsers":[{"name":"chromium","revision":"1244"},{"name":"chromium-headless-shell","revision":"1244"},
             {"name":"firefox","revision":"1544"}]}
EOF
prune_playwright > /dev/null
assert_eq "wanted chromium kept"                "$(yn test -d "$PW_CACHE_DIR/chromium-1244")" "yes"
assert_eq "old chromium removed"                "$(yn test -d "$PW_CACHE_DIR/chromium-1228")" "no"
assert_eq "wanted headless shell kept"          "$(yn test -d "$PW_CACHE_DIR/chromium_headless_shell-1244")" "yes"
assert_eq "old headless shell removed"          "$(yn test -d "$PW_CACHE_DIR/chromium_headless_shell-1228")" "no"
assert_eq "old firefox removed"                 "$(yn test -d "$PW_CACHE_DIR/firefox-1532")" "no"
assert_eq "browser not listed is left alone"    "$(yn test -d "$PW_CACHE_DIR/android-9")" "yes"
assert_eq "non-revision dir is left alone"      "$(yn test -d "$PW_CACHE_DIR/.links")" "yes"

# --- 3. Chromium temp profiles: only those idle for more than a day -------------------------------
mkdir -p "$CHROMIUM_PROFILE_DIR"/{scoped_dirOLD,scoped_dirNEW,Default}
touch -t 202001010000 "$CHROMIUM_PROFILE_DIR/scoped_dirOLD" "$CHROMIUM_PROFILE_DIR/Default"
prune_chromium_profiles
assert_eq "stale scoped_dir removed"            "$(yn test -d "$CHROMIUM_PROFILE_DIR/scoped_dirOLD")" "no"
assert_eq "fresh scoped_dir kept"               "$(yn test -d "$CHROMIUM_PROFILE_DIR/scoped_dirNEW")" "yes"
assert_eq "real profile never touched"          "$(yn test -d "$CHROMIUM_PROFILE_DIR/Default")" "yes"

# --- 4. options -----------------------------------------------------------------------------------
HELP="$(bash "$ROOT/scripts/vm-clean.sh" --help 2>&1)"; CODE=$?
assert_eq "--help exits 0"                      "$CODE" "0"
assert_eq "--help mentions Claude binaries"     "$(yn grep -q 'Claude Code binaries' <<<"$HELP")" "yes"
bash "$ROOT/scripts/vm-clean.sh" --bogus > /dev/null 2>&1; assert_eq "unknown option -> exit 2" "$?" "2"

suite_summary "vm-clean"
