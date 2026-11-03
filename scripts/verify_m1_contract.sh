#!/usr/bin/env bash
# ==============================================================================
# scripts/verify_m1_contract.sh
# Turnkey Verification & Audit Runner for Milestone 1
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_BOOTSTRAP_DIR="${WORKSPACE_ROOT}/terraform/00-bootstrap"

BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${BOLD}======================================================${RESET}"
echo -e "${BOLD}   Milestone 1 Quality & Contract Verification Audit  ${RESET}"
echo -e "${BOLD}======================================================${RESET}"
echo -e "Target Directory: ${TF_BOOTSTRAP_DIR}"
echo ""

FAILURES=0

record_pass() {
    echo -e "  [${GREEN}PASS${RESET}] $1"
}

record_fail() {
    echo -e "  [${RED}FAIL${RESET}] $1"
    FAILURES=$((FAILURES + 1))
}

# ------------------------------------------------------------------------------
# Phase 1: File Existence & Scaffold
# ------------------------------------------------------------------------------
echo -e "${YELLOW}Phase 1: Verifying File Scaffold...${RESET}"
REQUIRED_FILES=(
    "terraform/00-bootstrap/main.tf"
    "terraform/00-bootstrap/variables.tf"
    "terraform/00-bootstrap/outputs.tf"
    "terraform/00-bootstrap/versions.tf"
    "terraform/00-bootstrap/terraform.tfvars.example"
    ".gitignore"
    "README.md"
)

for rel_path in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${WORKSPACE_ROOT}/${rel_path}" ]]; then
        record_pass "File exists: ${rel_path}"
    else
        record_fail "Missing required file: ${rel_path}"
    fi
done

# ------------------------------------------------------------------------------
# Phase 2: Static Analysis & Canonical Formatting
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 2: Static Analysis & Formatting...${RESET}"
if terraform fmt -check -diff -recursive "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_pass "terraform fmt formatting check"
else
    record_fail "terraform fmt detected unformatted files"
fi

if (cd "${TF_BOOTSTRAP_DIR}" && terraform init -backend=false > /dev/null 2>&1); then
    record_pass "terraform init -backend=false"
else
    record_fail "terraform init -backend=false failed"
fi

VAL_OUTPUT=$(cd "${TF_BOOTSTRAP_DIR}" && terraform validate 2>&1)
if [[ $? -eq 0 ]]; then
    record_pass "terraform validate"
else
    record_fail "terraform validate failed:\n${VAL_OUTPUT}"
fi

# ------------------------------------------------------------------------------
# Phase 3: Interface Contract Outputs
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 3: Interface Contract Outputs...${RESET}"
CONTRACT_OUTPUTS=(
    "project_id"
    "project_number"
    "workstation_service_account_email"
    "wif_provider_name"
    "state_bucket_name"
    "secret_manager_ids"
    "ci_service_account_email"
)

for out in "${CONTRACT_OUTPUTS[@]}"; do
    if grep -E "output\s+\"${out}\"" "${TF_BOOTSTRAP_DIR}/outputs.tf" > /dev/null 2>&1; then
        record_pass "Contract output declared: ${out}"
    else
        record_fail "Contract output missing: ${out}"
    fi
done

# Check that sensitive = true is NOT declared on contract outputs
if grep -E "sensitive\s*=\s*true" "${TF_BOOTSTRAP_DIR}/outputs.tf" > /dev/null 2>&1; then
    record_fail "Outputs contain sensitive = true (contract requires non-sensitive metadata outputs)"
else
    record_pass "Zero outputs incorrectly masked with sensitive = true"
fi

# ------------------------------------------------------------------------------
# Phase 4: Secret Manager Security Policy
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 4: Secret Manager Security Policy (Zero-Payload)...${RESET}"
if grep -rn --exclude-dir=".terraform" --include="*.tf" "google_secret_manager_secret_version" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_fail "Violation: google_secret_manager_secret_version found in .tf files"
else
    record_pass "Zero google_secret_manager_secret_version resources in IaC"
fi

if grep -rn --exclude-dir=".terraform" --include="*.tf" "secret_data" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_fail "Violation: secret_data found in .tf files"
else
    record_pass "Zero secret_data assignments in IaC"
fi

# ------------------------------------------------------------------------------
# Phase 5: Organization Policy & IAM Safety
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 5: Org Policy & IAM Safety Checks...${RESET}"
if grep -rn --exclude-dir=".terraform" --include="*.tf" "google_service_account_key" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_fail "Violation: google_service_account_key found (prohibited by Org Policy)"
else
    record_pass "Zero service account key resources"
fi

if grep -rn "uniform_bucket_level_access\s*=\s*true" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_pass "Uniform bucket level access enforced on state bucket"
else
    record_fail "Missing uniform_bucket_level_access = true on state bucket"
fi

if grep -rn --exclude-dir=".terraform" --include="*.tf" "google_project_iam_binding" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1 || \
   grep -rn --exclude-dir=".terraform" --include="*.tf" "google_project_iam_policy" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_fail "Authoritative IAM bindings (google_project_iam_binding/policy) detected"
else
    record_pass "Non-authoritative IAM member bindings used exclusively"
fi

# ------------------------------------------------------------------------------
# Phase 6: WIF PrincipalSet String Pattern
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 6: Workload Identity Federation Format...${RESET}"
WIF_PATTERN='principalSet://iam\.googleapis\.com/.+/attribute\.repository/'
if grep -rnE "${WIF_PATTERN}" "${TF_BOOTSTRAP_DIR}" > /dev/null 2>&1; then
    record_pass "WIF IAM member follows Google STS standard principalSet:// syntax"
else
    record_fail "WIF IAM member syntax invalid or missing principalSet://iam.googleapis.com/..."
fi

# ------------------------------------------------------------------------------
# Phase 7: Native Terraform Test Execution
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 7: Native Terraform Test Suite...${RESET}"
if [[ -f "${TF_BOOTSTRAP_DIR}/tests/m1_boundary.tftest.hcl" ]]; then
    TEST_OUTPUT=$(cd "${TF_BOOTSTRAP_DIR}" && terraform test 2>&1)
    if [[ $? -eq 0 ]]; then
        record_pass "Native terraform test suite passed"
    else
        record_fail "terraform test failed:\n${TEST_OUTPUT}"
    fi
else
    echo -e "  [${YELLOW}WARN${RESET}] tests/m1_boundary.tftest.hcl not found. Skipping native test."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}======================================================${RESET}"
if [[ ${FAILURES} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}AUDIT SUCCESSFUL: 0 defects detected. Milestone 1 Verified.${RESET}"
    echo -e "${BOLD}======================================================${RESET}"
    exit 0
else
    echo -e "${RED}${BOLD}AUDIT FAILED: ${FAILURES} defect(s) detected. Fix required.${RESET}"
    echo -e "${BOLD}======================================================${RESET}"
    exit 1
fi
