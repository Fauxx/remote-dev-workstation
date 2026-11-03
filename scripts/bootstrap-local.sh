#!/usr/bin/env bash
# ==============================================================================
# scripts/bootstrap-local.sh
# Production IaC & CI/CD Cloud Mobile Workstation: Bootstrap & State Migration
#
# Automates the 3-phase bootstrap process:
#   Phase 0: Pre-flight Verification (CLI tools, GCP auth, GitHub auth)
#   Phase 1: Local Backend Init & Apply (Provisions GCP Project & GCS Bucket)
#   Phase 2: Remote State Migration (Generates backend.tf & migrates state to GCS)
#   Phase 3: GitHub Actions Variable Export (Exports outputs via gh variable set)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Terminal Color Codes & Logging Helpers
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# ------------------------------------------------------------------------------
# Directory Context Resolution
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${REPO_ROOT}/terraform/00-bootstrap"
WORKSTATION_DIR="${REPO_ROOT}/terraform/01-workstation"

log_info "Repository root: ${REPO_ROOT}"
log_info "Bootstrap directory: ${BOOTSTRAP_DIR}"

# ------------------------------------------------------------------------------
# Phase 0: Pre-flight Verification
# ------------------------------------------------------------------------------
log_info "Starting Phase 0: Pre-flight checks..."

for cmd in terraform gcloud gh git; do
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "Required tool '${cmd}' is not installed or not in PATH."
        exit 1
    fi
done

# Verify gcloud authentication
ACTIVE_GCP_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [ -z "${ACTIVE_GCP_ACCOUNT}" ]; then
    log_error "No active GCP account found in gcloud. Run 'gcloud auth login' first."
    exit 1
fi
log_success "Active GCP account: ${ACTIVE_GCP_ACCOUNT}"

# Verify GitHub CLI authentication
if ! gh auth status &>/dev/null; then
    log_error "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first."
    exit 1
fi
GITHUB_USER=$(gh api user -q .login 2>/dev/null || echo "Unknown")
log_success "Active GitHub account: ${GITHUB_USER}"

# Identify GitHub repository
GITHUB_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "Fauxx/remote-dev-workstation")
log_info "Target GitHub repository: ${GITHUB_REPO}"

# ------------------------------------------------------------------------------
# Phase 1: Local Backend Init & Apply
# ------------------------------------------------------------------------------
log_info "Starting Phase 1: Initializing and applying 00-bootstrap..."

cd "${BOOTSTRAP_DIR}"

# Check if state has already been migrated to GCS
ALREADY_MIGRATED=false
if [ -f "backend.tf" ]; then
    if grep -q 'backend "gcs"' backend.tf; then
        log_info "Found existing backend.tf with GCS backend. Verifying remote state connectivity..."
        if terraform init -input=false -backend=true &>/dev/null; then
            log_success "Remote GCS backend is already active and healthy."
            ALREADY_MIGRATED=true
        else
            log_warn "backend.tf exists but remote state failed to initialize. Reverting to local state..."
            mv backend.tf backend.tf.bak
        fi
    fi
fi

if [ "${ALREADY_MIGRATED}" = false ]; then
    # Clean local initialization
    log_info "Running 'terraform init -input=false' with local state backend..."
    terraform init -input=false

    log_info "Applying 00-bootstrap infrastructure (GCP project, APIs, GCS state bucket, WIF, SAs)..."
    terraform apply -auto-approve -input=false
    log_success "Phase 1 complete: Infrastructure provisioned successfully."
fi

# ------------------------------------------------------------------------------
# Extract Terraform Outputs
# ------------------------------------------------------------------------------
log_info "Extracting outputs from 00-bootstrap..."

STATE_BUCKET=$(terraform output -raw state_bucket_name 2>/dev/null || true)
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || true)
PROJECT_NUMBER=$(terraform output -raw project_number 2>/dev/null || true)
WIF_PROVIDER=$(terraform output -raw wif_provider_name 2>/dev/null || true)
CICD_SA=$(terraform output -raw ci_service_account_email 2>/dev/null || terraform output -raw cicd_service_account_email 2>/dev/null || true)
WORKSTATION_SA=$(terraform output -raw workstation_service_account_email 2>/dev/null || true)

if [ -z "${STATE_BUCKET}" ] || [ -z "${PROJECT_ID}" ] || [ -z "${WIF_PROVIDER}" ]; then
    log_error "Failed to retrieve critical outputs from Terraform. Aborting."
    exit 1
fi

log_success "Extracted Outputs:"
echo "  - GCP Project ID:        ${PROJECT_ID}"
echo "  - State Bucket Name:     ${STATE_BUCKET}"
echo "  - WIF Provider:          ${WIF_PROVIDER}"
echo "  - CI/CD Service Account: ${CICD_SA}"
echo "  - Workstation SA:        ${WORKSTATION_SA}"

# ------------------------------------------------------------------------------
# Phase 2: Remote State Migration
# ------------------------------------------------------------------------------
log_info "Starting Phase 2: Migrating Terraform state to Cloud Storage (GCS)..."

if [ "${ALREADY_MIGRATED}" = false ]; then
    # Dynamically generate backend.tf for 00-bootstrap
    log_info "Generating ${BOOTSTRAP_DIR}/backend.tf..."
    cat <<EOF > "${BOOTSTRAP_DIR}/backend.tf"
# Generated dynamically by scripts/bootstrap-local.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Remote state storage in GCS bucket: ${STATE_BUCKET}
terraform {
  backend "gcs" {
    bucket = "${STATE_BUCKET}"
    prefix = "terraform/state/00-bootstrap"
  }
}
EOF

    log_info "Running 'terraform init -migrate-state -force-copy'..."
    terraform init -migrate-state -force-copy -input=false

    # Confirm GCS state object is accessible
    if command -v gcloud &>/dev/null; then
        if gcloud storage ls "gs://${STATE_BUCKET}/terraform/state/00-bootstrap/" &>/dev/null; then
            log_success "Confirmed remote state object exists in gs://${STATE_BUCKET}/terraform/state/00-bootstrap/"
        elif gsutil ls "gs://${STATE_BUCKET}/terraform/state/00-bootstrap/" &>/dev/null; then
            log_success "Confirmed remote state object exists via gsutil"
        fi
    fi

    # Archive local state file to prevent local desync
    if [ -f "terraform.tfstate" ]; then
        mv terraform.tfstate terraform.tfstate.migrated.backup
        log_info "Archived local state file to terraform.tfstate.migrated.backup"
    fi

    log_success "Phase 2 complete: State successfully migrated to remote GCS bucket."
else
    log_info "State was previously migrated. Skipping migration step."
fi

# Pre-seed 01-workstation backend.tf and variables
if [ -d "${WORKSTATION_DIR}" ]; then
    log_info "Pre-configuring ${WORKSTATION_DIR}/backend.tf..."
    cat <<EOF > "${WORKSTATION_DIR}/backend.tf"
# Generated dynamically by scripts/bootstrap-local.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Remote state storage in GCS bucket: ${STATE_BUCKET}
terraform {
  backend "gcs" {
    bucket = "${STATE_BUCKET}"
    prefix = "terraform/state/01-workstation"
  }
}
EOF
    log_success "Generated ${WORKSTATION_DIR}/backend.tf"

    cat <<EOF > "${WORKSTATION_DIR}/terraform.tfvars"
state_bucket_name = "${STATE_BUCKET}"
project_id        = "${PROJECT_ID}"
EOF
    log_success "Generated ${WORKSTATION_DIR}/terraform.tfvars"
fi

# ------------------------------------------------------------------------------
# Phase 3: Export GitHub Repository Variables
# ------------------------------------------------------------------------------
log_info "Starting Phase 3: Populating GitHub repository variables..."

cd "${REPO_ROOT}"

log_info "Setting GCP_PROJECT_ID=${PROJECT_ID}..."
gh variable set GCP_PROJECT_ID --body "${PROJECT_ID}" --repo "${GITHUB_REPO}"

log_info "Setting GCP_WORKLOAD_IDENTITY_PROVIDER=${WIF_PROVIDER}..."
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "${WIF_PROVIDER}" --repo "${GITHUB_REPO}"

log_info "Setting GCP_SERVICE_ACCOUNT=${CICD_SA}..."
gh variable set GCP_SERVICE_ACCOUNT --body "${CICD_SA}" --repo "${GITHUB_REPO}"

log_info "Setting GCP_STATE_BUCKET=${STATE_BUCKET}..."
gh variable set GCP_STATE_BUCKET --body "${STATE_BUCKET}" --repo "${GITHUB_REPO}"

log_success "Phase 3 complete: All repository variables populated in ${GITHUB_REPO}."

# Print variable verification
echo ""
log_info "Active GitHub Repository Variables:"
gh variable list --repo "${GITHUB_REPO}"

# ------------------------------------------------------------------------------
# Execution Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}               BOOTSTRAP & STATE MIGRATION COMPLETE!                         ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Project ID:                     ${CYAN}${PROJECT_ID}${NC}"
echo -e "Remote State Bucket:            ${CYAN}${STATE_BUCKET}${NC}"
echo -e "WIF Provider:                   ${CYAN}${WIF_PROVIDER}${NC}"
echo -e "CI/CD Service Account:          ${CYAN}${CICD_SA}${NC}"
echo -e "Workstation Service Account:    ${CYAN}${WORKSTATION_SA}${NC}"
echo -e "Target GitHub Repo:             ${CYAN}${GITHUB_REPO}${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "Next steps:"
echo -e "  1. Stage and commit generated backend.tf files:"
echo -e "     git add terraform/00-bootstrap/backend.tf terraform/01-workstation/backend.tf"
echo -e "     git commit -m 'chore(terraform): configure remote GCS backend after bootstrap migration'"
echo -e "     git push origin main"
echo -e "  2. Proceed to Milestone 2 (01-workstation IaC and startup provisioning)."
echo -e "${GREEN}==============================================================================${NC}"
