#!/usr/bin/env bash
# scripts/check-gcp-wif.sh — read-only check: can YOU set up GitHub Actions OIDC / Workload
# Identity Federation (WIF) on a GCP project? Pick an authenticated account, pick a project,
# test the IAM permissions, and print a clear verdict.
#
# Run on the HOST — gcloud creds live there; the VM holds no cloud auth (see CLAUDE.md,
# "Isolated VM"). Strictly read-only. It does NOT touch the Org Policy API: reading org policies
# needs org-admin access we don't require. Domain Restricted Sharing, if your org enforces it,
# surfaces as a clear error at SETUP time (the GitHub-principal binding) — not here.
#   Usage: ./scripts/check-gcp-wif.sh [PROJECT_ID]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "GCP Workload Identity Federation — can you set it up? (read-only)"
has gcloud || die "gcloud not found. Install: brew install --cask google-cloud-sdk   (then: gcloud init)."

# --- 1) pick the authenticated account -------------------------------------
accounts=()
while IFS= read -r a; do [ -n "$a" ] && accounts+=("$a"); done \
  < <(gcloud auth list --format='value(account)' 2>/dev/null || true)
if [ "${#accounts[@]}" -eq 0 ]; then
  die "No authenticated gcloud account. Run:  gcloud auth login   then re-run this."
elif [ "${#accounts[@]}" -eq 1 ]; then
  ACCOUNT="${accounts[0]}"
else
  info "Choose the GCP account:"
  PS3="account # > "
  select ACCOUNT in "${accounts[@]}"; do [ -n "${ACCOUNT:-}" ] && break; done
fi
ok "Account: $ACCOUNT"

# --- 2) pick the project ---------------------------------------------------
PROJECT="${1:-}"
if [ -z "$PROJECT" ]; then
  info "Fetching projects visible to $ACCOUNT …"
  projects=()
  while IFS= read -r p; do [ -n "$p" ] && projects+=("$p"); done \
    < <(gcloud projects list --account="$ACCOUNT" --sort-by=projectId --format='value(projectId)' 2>/dev/null || true)
  [ "${#projects[@]}" -gt 0 ] || die "No projects visible (or list permission denied) for $ACCOUNT."
  info "Choose the project to check (${#projects[@]} found):"
  PS3="project # > "
  select PROJECT in "${projects[@]}"; do [ -n "${PROJECT:-}" ] && break; done
fi
ok "Project: $PROJECT"

# --- 3) IAM permissions needed to set up WIF (the decisive, no-special-access check) -------
req=(iam.workloadIdentityPools.create iam.workloadIdentityPoolProviders.create \
     iam.serviceAccounts.create iam.serviceAccounts.setIamPolicy \
     resourcemanager.projects.setIamPolicy serviceusage.services.enable)
info "Testing your IAM permissions on $PROJECT …"
log ""
have="$(gcloud --account="$ACCOUNT" --quiet projects test-iam-permissions "$PROJECT" \
        --permissions="$(IFS=,; printf '%s' "${req[*]}")" \
        --format='value(permissions)' </dev/null 2>/dev/null || true)"
missing=()
for p in "${req[@]}"; do
  if printf '%s\n' "$have" | grep -qx "$p"; then
    ok "  have     $p"
  else
    warn "  MISSING  $p"
    missing+=("$p")
  fi
done

# --- verdict ---------------------------------------------------------------
log ""
step "Verdict — project $PROJECT (account $ACCOUNT)"
log ""
if [ "${#missing[@]}" -eq 0 ]; then
  ok "FEASIBLE — you have all ${#req[@]} permissions to set up WIF on this project yourself."
  log ""
  log "  Next: ask me to generate the Workload Identity Pool + GitHub provider + service account"
  log "        + deploy workflow for $PROJECT."
else
  warn "NOT YET — missing ${#missing[@]} of ${#req[@]} permission(s) (listed above)."
  log ""
  log "  → Grant them with ./scripts/enable-gcp-wif.sh (or have an admin run it):"
  log "      roles/iam.workloadIdentityPoolAdmin"
  log "      roles/iam.serviceAccountAdmin"
  log "      roles/resourcemanager.projectIamAdmin"
  log "      roles/serviceusage.serviceUsageAdmin"
fi
log ""
log "  Note: Domain Restricted Sharing is intentionally NOT checked (reading org policy needs"
log "  org-admin access). If your org enforces it, the GitHub-principal IAM binding will fail"
log "  with a clear error during setup — then ask an admin for a one-time exception. No need to"
log "  verify it in advance."
