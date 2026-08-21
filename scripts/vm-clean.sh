#!/usr/bin/env bash
# vm-clean — reclaim space on the VM's SMALL root filesystem (/).
#
# The VM's root disk is ~19 GB and is SEPARATE from the 60 GB Docker data disk
# (/mnt/lima-colima). Caches under ~ and the Claude scratchpad under /tmp are what
# fill root up — this clears the re-downloadable ones plus stale scratchpad.
#
# SAFE by design — it NEVER touches: your code (~/Projects, on the host mount), git,
# credentials, or installed toolchains (rustup, Node, uv-managed Pythons, Playwright
# browsers under ~/.cache/ms-playwright). Only caches (re-fetched on next use) and
# stale temp files. Docker's store is on the other disk — clear it with --docker.
#
# Usage: vm-clean [--docker] [--scratch-all]
#   --docker       also `docker system prune -f` (frees /mnt/lima-colima, not root)
#   --scratch-all  purge ALL Claude scratchpad dirs, not just those idle >60 min
set -uo pipefail

DOCKER=0; SCRATCH_ALL=0
for a in "$@"; do
  case "$a" in
    --docker)      DOCKER=1 ;;
    --scratch-all) SCRATCH_ALL=1 ;;
    -h|--help)     sed -n '2,14{/^# /p;}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

avail_kb() { df -Pk / | awk 'NR==2{print $4}'; }
line()     { df -Ph / | awk 'NR==2{printf "used %s / %s (%s), free %s\n",$3,$2,$5,$4}'; }

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
command -v npm    >/dev/null 2>&1 && npm cache clean --force        >/dev/null 2>&1 || true
command -v uv     >/dev/null 2>&1 && uv cache clean                 >/dev/null 2>&1 || true
command -v pip3   >/dev/null 2>&1 && pip3 cache purge               >/dev/null 2>&1 || true
command -v go     >/dev/null 2>&1 && go clean -cache -modcache      >/dev/null 2>&1 || true
command -v dotnet >/dev/null 2>&1 && dotnet nuget locals all --clear >/dev/null 2>&1 || true
# Cargo: registry download cache only — keep ~/.cargo/bin and the ~/.rustup toolchains.
rm -rf "$HOME"/.cargo/registry/cache "$HOME"/.cargo/registry/src 2>/dev/null || true
# Maven: the local repo is a re-downloadable cache.
rm -rf "$HOME"/.m2/repository 2>/dev/null || true
# apt package archives.
sudo apt-get clean >/dev/null 2>&1 || true

# 3) Docker (separate disk) — opt-in, since it does NOT free root.
if [ "$DOCKER" = 1 ] && command -v docker >/dev/null 2>&1; then
  docker system prune -f >/dev/null 2>&1 || true
fi

after="$(avail_kb)"
echo "root / after:  $(line)"
echo "reclaimed on /: $(( (after - before) / 1024 )) MB"
