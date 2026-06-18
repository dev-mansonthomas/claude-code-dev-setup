#!/usr/bin/env bash
# scripts/enable-gcp-wif.sh — grant the IAM roles needed to SET UP GitHub Actions OIDC / Workload
# Identity Federation on a GCP project. MUTATING (it adds IAM role bindings). Run on the HOST.
#
# The caller needs resourcemanager.projects.setIamPolicy (Owner / Project IAM Admin). If you don't
# have it (e.g. a corporate org), the script instead PRINTS the exact commands for an admin to run.
# It only grants the *setup* roles — it does NOT create the pool/provider/service account; that's
# the next, project-specific step (ask Claude to generate it once check-gcp-wif.sh says FEASIBLE).
#   Usage: ./scripts/enable-gcp-wif.sh [PROJECT_ID] [PRINCIPAL]
#     PRINCIPAL = who receives the roles (the identity that will run the WIF setup). Default: the
#     active account. A bare email is auto-prefixed (user:/serviceAccount:); or pass a full member.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

ROLES=(roles/iam.workloadIdentityPoolAdmin roles/iam.serviceAccountAdmin \
       roles/resourcemanager.projectIamAdmin roles/serviceusage.serviceUsageAdmin)

step "Grant IAM roles for Workload Identity Federation setup (MUTATING)"
has gcloud || die "gcloud not found. Install: brew install --cask google-cloud-sdk   (then: gcloud init)."

# --- pick the account that will perform the grant --------------------------
accounts=()
while IFS= read -r a; do [ -n "$a" ] && accounts+=("$a"); done \
  < <(gcloud auth list --format='value(account)' 2>/dev/null || true)
if [ "${#accounts[@]}" -eq 0 ]; then
  die "No authenticated gcloud account. Run:  gcloud auth login"
elif [ "${#accounts[@]}" -eq 1 ]; then
  ACCOUNT="${accounts[0]}"
else
  info "Choose the GCP account (must be able to set IAM policy):"
  PS3="account # > "
  select ACCOUNT in "${accounts[@]}"; do [ -n "${ACCOUNT:-}" ] && break; done
fi
ok "Acting as: $ACCOUNT"

# --- pick the project ------------------------------------------------------
PROJECT="${1:-}"
if [ -z "$PROJECT" ]; then
  info "Fetching projects visible to $ACCOUNT …"
  projects=()
  while IFS= read -r p; do [ -n "$p" ] && projects+=("$p"); done \
    < <(gcloud projects list --account="$ACCOUNT" --sort-by=projectId --format='value(projectId)' 2>/dev/null || true)
  [ "${#projects[@]}" -gt 0 ] || die "No projects visible for $ACCOUNT."
  info "Choose the project (${#projects[@]} found):"
  PS3="project # > "
  select PROJECT in "${projects[@]}"; do [ -n "${PROJECT:-}" ] && break; done
fi
ok "Project: $PROJECT"

# --- resolve the principal that will receive the roles ---------------------
PRINCIPAL_IN="${2:-$ACCOUNT}"
case "$PRINCIPAL_IN" in
  *:*)                   MEMBER="$PRINCIPAL_IN" ;;
  *.gserviceaccount.com) MEMBER="serviceAccount:$PRINCIPAL_IN" ;;
  *)                     MEMBER="user:$PRINCIPAL_IN" ;;
esac
ok "Grant to: $MEMBER"
info "Roles (${#ROLES[@]}): ${ROLES[*]}"

# --- if the caller can't set IAM policy, hand the commands to an admin -----
can="$(gcloud --account="$ACCOUNT" --quiet projects test-iam-permissions "$PROJECT" \
       --permissions=resourcemanager.projects.setIamPolicy --format='value(permissions)' </dev/null 2>/dev/null || true)"
if ! printf '%s' "$can" | grep -q 'resourcemanager.projects.setIamPolicy'; then
  log ""
  warn "$ACCOUNT cannot set IAM policy on $PROJECT (needs Owner / Project IAM Admin)."
  log  "→ Send these commands to a project admin (they grant the WIF-setup roles to $MEMBER):"
  log  ""
  for r in "${ROLES[@]}"; do
    log "    gcloud projects add-iam-policy-binding $PROJECT --member='$MEMBER' --role='$r' --condition=None"
  done
  exit 0
fi

# --- confirm (mutating), then grant ----------------------------------------
log ""
warn "About to ADD ${#ROLES[@]} IAM role binding(s) on $PROJECT for $MEMBER."
printf 'Proceed? [y/N] '
read -r reply </dev/tty 2>/dev/null || reply=""
case "$reply" in [Yy]*) ;; *) info "Aborted — no changes made."; exit 0 ;; esac

rc=0
for r in "${ROLES[@]}"; do
  info "Granting $r …"
  if gcloud --account="$ACCOUNT" --quiet projects add-iam-policy-binding "$PROJECT" \
       --member="$MEMBER" --role="$r" --condition=None >/dev/null 2>&1; then
    ok "  granted $r"
  else
    warn "  could not grant $r (denied, or already present)"; rc=1
  fi
done

log ""
if [ "$rc" -eq 0 ]; then
  ok "Done. Verify:  ./scripts/check-gcp-wif.sh $PROJECT   → should now say FEASIBLE."
  log "   Then ask Claude to generate the pool + provider + service account + deploy.yml."
else
  warn "Some grants failed — review above (insufficient role, or already set)."
fi
