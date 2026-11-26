#!/usr/bin/env bash
# vm-clean — reclaim space on the VM's SMALL root filesystem (/).
#
# The VM's root disk is ~19 GB and is SEPARATE from the 60 GB Docker data disk
# (/mnt/lima-colima). Caches under ~ and the Claude scratchpad under /tmp are what
# fill root up — this clears the re-downloadable ones plus stale scratchpad.
#
# SAFE by design — it NEVER touches: your code (~/Projects, on the host mount), git,
# credentials, or installed toolchains (rustup, Node, uv-managed Pythons). It also prunes
# what silently piles up: old Claude Code binaries (not the current one, not one a running
# session uses), Playwright browser revisions the pinned Playwright no longer uses, and
# Chromium temp profiles abandoned for more than a day. Docker is on the other disk: --docker.
#
# Usage: vm-clean [--docker] [--scratch-all]
#   --docker       also `docker system prune -f` (frees /mnt/lima-colima, not root)
#   --scratch-all  purge ALL Claude scratchpad dirs, not just those idle >60 min
set -uo pipefail

# Paths are overridable for the test suite (tests/test-vm-clean.sh); defaults are the VM's.
CLAUDE_VERSIONS_DIR="${CLAUDE_VERSIONS_DIR:-$HOME/.local/share/claude/versions}"
PW_CACHE_DIR="${PW_CACHE_DIR:-$HOME/.cache/ms-playwright}"
CHROMIUM_PROFILE_DIR="${CHROMIUM_PROFILE_DIR:-$HOME/.config/chromium-headless}"

avail_kb() { df -Pk / | awk 'NR==2{print $4}'; }
line()     { df -Ph / | awk 'NR==2{printf "used %s / %s (%s), free %s\n",$3,$2,$5,$4}'; }

# Claude binaries that must stay: the one `claude` resolves to, plus every one a running
# session was started from (deleting those frees nothing until the session exits anyway).
claude_in_use() {
  local p
  command -v claude >/dev/null 2>&1 && readlink -f "$(command -v claude)"
  for p in $(pgrep -x claude 2>/dev/null); do readlink -f "/proc/$p/exe" 2>/dev/null; done
}

# Old Claude Code versions: the native installer keeps every past binary (300-400 MB each),
# and a failed self-update (e.g. disk full) leaves a 0-byte file behind.
prune_claude_versions() {
  local keep v
  [ -d "$CLAUDE_VERSIONS_DIR" ] || return 0
  keep="$(claude_in_use)"
  [ -n "$keep" ] || { echo "claude versions: none resolved as current — skipped (safety)"; return 0; }
  for v in "$CLAUDE_VERSIONS_DIR"/*; do
    [ -e "$v" ] || continue
    printf '%s\n' "$keep" | grep -qxF -- "$(readlink -f "$v")" && continue   # exact, resolved match
    rm -f -- "$v" && echo "removed claude $(basename "$v")"
  done
}

# Browser revisions wanted by the installed (pinned) Playwright, as cache dir names
# (`chromium-headless-shell` + 1244 -> `chromium_headless_shell-1244`).
pw_wanted() {
  local root f
  root="$(npm root -g 2>/dev/null)" || return 1
  for f in "$root/playwright/node_modules/playwright-core/browsers.json" "$root/playwright-core/browsers.json"; do
    [ -f "$f" ] && { jq -r '.browsers[] | "\(.name | gsub("-"; "_"))-\(.revision)"' "$f"; return; }
  done
  return 1
}

# Remove a revision dir only when the pinned Playwright wants ANOTHER revision of that same
# browser; browsers it doesn't list, and anything not shaped <name>-<rev>, are left alone.
prune_playwright() {
  local wanted d base
  [ -d "$PW_CACHE_DIR" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  wanted="$(pw_wanted)" || { echo "playwright: pinned version not found — skipped (safety)"; return 0; }
  [ -n "$wanted" ] || return 0
  for d in "$PW_CACHE_DIR"/*-[0-9]*; do
    [ -d "$d" ] || continue
    base="$(basename "$d")"
    printf '%s\n' "$wanted" | grep -qxF "$base" && continue
    printf '%s\n' "$wanted" | grep -q "^${base%-*}-[0-9]*\$" || continue
    rm -rf -- "$d" && echo "removed playwright $base"
  done
}

# Chromium headless temp profiles (scoped_dir*) left behind by killed runs, ~200 MB each.
prune_chromium_profiles() {
  [ -d "$CHROMIUM_PROFILE_DIR" ] || return 0
  find "$CHROMIUM_PROFILE_DIR" -maxdepth 1 -name 'scoped_dir*' -mtime +1 -exec rm -rf {} + 2>/dev/null || true
}

main() {
  local DOCKER=0 SCRATCH_ALL=0 a before after
  for a in "$@"; do
    case "$a" in
      --docker)      DOCKER=1 ;;
      --scratch-all) SCRATCH_ALL=1 ;;
      -h|--help)     sed -n '2,16{/^# /p;}' "$0" | sed 's/^# \{0,1\}//'; return 0 ;;
      *)             echo "unknown option: $a (try --help)" >&2; return 2 ;;
    esac
  done

  before="$(avail_kb)"
  echo "root / before: $(line)"

  # 1) Claude scratchpad — usually the biggest (downloaded provider binaries, build artifacts).
  #    Default: only dirs idle for >60 min (spare the active session); --scratch-all: everything.
  if [ "$SCRATCH_ALL" = 1 ]; then
    find /tmp/claude-* -type d -name scratchpad -prune -exec rm -rf {} + 2>/dev/null || true
  else
    find /tmp/claude-* -type d -name scratchpad -mmin +60 -prune -exec rm -rf {} + 2>/dev/null || true
  fi

  # 2) Package-manager download caches — all re-fetched on next build/install.
  if command -v npm    >/dev/null 2>&1; then npm cache clean --force        >/dev/null 2>&1 || true; fi
  if command -v uv     >/dev/null 2>&1; then uv cache clean                 >/dev/null 2>&1 || true; fi
  if command -v pip3   >/dev/null 2>&1; then pip3 cache purge               >/dev/null 2>&1 || true; fi
  if command -v go     >/dev/null 2>&1; then go clean -cache -modcache      >/dev/null 2>&1 || true; fi
  if command -v dotnet >/dev/null 2>&1; then dotnet nuget locals all --clear >/dev/null 2>&1 || true; fi
  # Cargo: registry download cache only — keep ~/.cargo/bin and the ~/.rustup toolchains.
  rm -rf "$HOME"/.cargo/registry/cache "$HOME"/.cargo/registry/src 2>/dev/null || true
  # Maven: the local repo is a re-downloadable cache.
  rm -rf "$HOME"/.m2/repository 2>/dev/null || true
  # apt package archives.
  sudo apt-get clean >/dev/null 2>&1 || true

  # 3) What piles up silently: old Claude binaries, stale Playwright revisions, Chromium temp profiles.
  prune_claude_versions
  prune_playwright
  prune_chromium_profiles

  # 4) Docker (separate disk) — opt-in, since it does NOT free root.
  if [ "$DOCKER" = 1 ] && command -v docker >/dev/null 2>&1; then
    docker system prune -f >/dev/null 2>&1 || true
  fi

  after="$(avail_kb)"
  echo "root / after:  $(line)"
  echo "reclaimed on /: $(( (after - before) / 1024 )) MB"
}

# Run only when executed (`vm-clean`), not when sourced by the tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
