#!/usr/bin/env bash
# scripts/check-gcp-wif.sh — read-only feasibility check for GitHub Actions OIDC / Workload
# Identity Federation (WIF) on a GCP project: pick an authenticated account, pick a project,
# run the IAM-permission + org-policy checks, and print an automatic verdict.
#
# Run on the HOST — gcloud creds live there; the VM holds no cloud auth (see CLAUDE.md,
# "Isolated VM"). Strictly read-only: it only lists / describes / tests, never changes anything.
#   Usage: ./scripts/check-gcp-wif.sh [PROJECT_ID]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

step "GCP Workload Identity Federation — feasibility check (read-only)"
has gcloud || die "gcloud not found. Install: brew install --cask google-cloud-sdk   (then: gcloud init)."
has jq     || die "jq not found: brew install jq."

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
GC=(gcloud --account="$ACCOUNT" --quiet)   # --quiet: never prompt (e.g. "enable API?") → never hang

# --- 3) IAM permissions needed to set up WIF -------------------------------
req=(iam.workloadIdentityPools.create iam.workloadIdentityPoolProviders.create \
     iam.serviceAccounts.create iam.serviceAccounts.setIamPolicy \
     resourcemanager.projects.setIamPolicy serviceusage.services.enable)
info "Testing IAM permissions on $PROJECT …"
have="$("${GC[@]}" projects test-iam-permissions "$PROJECT" \
        --permissions="$(IFS=,; printf '%s' "${req[*]}")" \
        --format='value(permissions)' </dev/null 2>/dev/null || true)"
missing=()
for p in "${req[@]}"; do
  printf '%s\n' "$have" | grep -qx "$p" || missing+=("$p")
done

# --- helper: org-policy constraint state. Echoes "STATE|HINT" (STATE: restrictive|ok|unknown).
# stdin is closed so a hidden "enable API?" prompt can't hang it; on failure, explain why.
policy_state() {
  local json errf hint; errf="$(mktemp "${TMPDIR:-/tmp}/wifchk.XXXXXX")"
  if json="$("${GC[@]}" org-policies describe "$1" --project="$PROJECT" --effective --format=json </dev/null 2>"$errf")"; then
    rm -f "$errf"
    if printf '%s' "$json" | jq -e '([.spec.rules[]?.values.allowedValues // [] | length] | add // 0) > 0' >/dev/null 2>&1; then
      echo "restrictive|"
    else
      echo "ok|"
    fi
  else
    if grep -qiE 'not enabled|SERVICE_DISABLED|orgpolicy\.googleapis' "$errf"; then
      hint="Org Policy API is off — enable once:  gcloud services enable orgpolicy.googleapis.com --project=$PROJECT  then re-run."
    elif grep -qiE 'permission|denied' "$errf"; then
      hint="you lack the org-policy viewer (orgpolicy.policy.get) — ask an admin to check, or to run this."
    else
      hint="$(tr '\n' ' ' < "$errf" | cut -c1-160)"
    fi
    rm -f "$errf"
    echo "unknown|$hint"
  fi
}

info "Reading org policy: Domain Restricted Sharing …"
drs_out="$(policy_state constraints/iam.allowedPolicyMemberDomains)"; drs_state="${drs_out%%|*}"; drs_hint="${drs_out#*|}"
info "Reading org policy: allowed WIF providers …"
wifp_out="$(policy_state constraints/iam.workloadIdentityPoolProviders)"; wifp_state="${wifp_out%%|*}"

# --- verdict ---------------------------------------------------------------
log ""
step "Verdict — $PROJECT"
if [ "${#missing[@]}" -eq 0 ]; then
  ok "IAM: you have all permissions to set up WIF."
else
  warn "IAM: missing ${#missing[@]} — ${missing[*]}"
  log  "     → ask for roles/iam.workloadIdentityPoolAdmin + roles/iam.serviceAccountAdmin + roles/resourcemanager.projectIamAdmin (or have an admin do the setup)."
fi
case "$drs_state" in
  ok)          ok   "Org policy: Domain Restricted Sharing does not block external principals." ;;
  restrictive) warn "Org policy: Domain Restricted Sharing is ENFORCED → binding the GitHub OIDC principal will be DENIED without an org-admin exception." ;;
  *)           warn "Org policy: couldn't read Domain Restricted Sharing — ${drs_hint:-verify with an admin}." ;;
esac
case "$wifp_state" in
  restricted|restrictive) warn "Org policy: WIF providers restricted → confirm an admin allows issuer https://token.actions.githubusercontent.com." ;;
  ok)                     ok   "Org policy: WIF providers not restricted." ;;
  *)                      : ;;
esac

log ""
if [ "${#missing[@]}" -eq 0 ] && [ "$drs_state" = ok ] && [ "$wifp_state" != restrictive ]; then
  ok "FEASIBLE — you can set up GitHub Actions OIDC / WIF on $PROJECT yourself."
  log "   Next: ask me to generate the pool + provider + service account + deploy.yml for $PROJECT."
elif [ "$drs_state" = restrictive ]; then
  warn "BLOCKED by org policy (Domain Restricted Sharing). Keyless WIF needs an org-admin exception for the GitHub principal — or use an account/org without DRS."
elif [ "${#missing[@]}" -gt 0 ]; then
  warn "NOT YET — you're missing IAM permissions (above). Get the roles, or have an admin run the setup."
else
  warn "LIKELY OK but unverified — re-run with org-policy viewer access, or confirm the org policies with an admin."
fi
