#!/usr/bin/env bash
# ==============================================================================
# scripts/verify_m3_cicd.sh
# Turnkey Verification & Audit Runner for Milestone 3 (CI/CD & Portfolio Docs)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKFLOWS_DIR="${WORKSPACE_ROOT}/.github/workflows"
PLAN_WORKFLOW="${WORKFLOWS_DIR}/terraform-plan.yml"
APPLY_WORKFLOW="${WORKFLOWS_DIR}/terraform-apply.yml"
README_FILE="${WORKSPACE_ROOT}/README.md"

BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo -e "${BOLD}========================================================================${RESET}"
echo -e "${BOLD}   Milestone 3 Quality, CI/CD Workflows & Portfolio Documentation Audit ${RESET}"
echo -e "${BOLD}========================================================================${RESET}"
echo -e "Workspace Root:   ${WORKSPACE_ROOT}"
echo -e "Workflows Dir:    ${WORKFLOWS_DIR}"
echo -e "README File:      ${README_FILE}"
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
echo -e "${YELLOW}Phase 1: Verifying Milestone 3 File Scaffold...${RESET}"
REQUIRED_FILES=(
    ".github/workflows/terraform-plan.yml"
    ".github/workflows/terraform-apply.yml"
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
# Phase 2: Workflow YAML Syntax & Event Triggers
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 2: Workflow YAML Syntax & Event Triggers...${RESET}"

if python3 -c "import yaml; yaml.safe_load(open('${PLAN_WORKFLOW}')); yaml.safe_load(open('${APPLY_WORKFLOW}'))" 2>/dev/null; then
    record_pass "YAML parser validated syntax of both workflow definitions"
else
    record_fail "YAML syntax validation failed on workflow files"
fi

# PR Plan trigger check
if grep -qE "pull_request:" "${PLAN_WORKFLOW}" && \
   grep -qE "branches:\s*\[\s*main\s*\]" "${PLAN_WORKFLOW}" && \
   grep -qE "workflow_dispatch:" "${PLAN_WORKFLOW}"; then
    record_pass "Plan workflow triggers on PR to main branch and supports manual workflow_dispatch"
else
    record_fail "Plan workflow trigger definitions invalid or missing"
fi

# Apply trigger check
if grep -qE "push:" "${APPLY_WORKFLOW}" && \
   grep -qE "branches:\s*\[\s*main\s*\]" "${APPLY_WORKFLOW}" && \
   grep -qE "workflow_dispatch:" "${APPLY_WORKFLOW}"; then
    record_pass "Apply workflow triggers on push to main branch and supports manual workflow_dispatch"
else
    record_fail "Apply workflow trigger definitions invalid or missing"
fi

# ------------------------------------------------------------------------------
# Phase 3: Concurrency Mutex & Race Condition Prevention
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 3: Concurrency Mutex & Race Condition Prevention...${RESET}"

# Plan concurrency: cancel-in-progress: true (abort obsolete PR runs)
if grep -qE "concurrency:" "${PLAN_WORKFLOW}" && \
   grep -qE "cancel-in-progress:\s*true" "${PLAN_WORKFLOW}"; then
    record_pass "Plan workflow concurrency configured with cancel-in-progress: true"
else
    record_fail "Plan workflow concurrency missing or cancel-in-progress is not true"
fi

# Apply concurrency: cancel-in-progress: false (MANDATORY mutex to prevent corrupted state lock)
if grep -qE "concurrency:" "${APPLY_WORKFLOW}" && \
   grep -qE "cancel-in-progress:\s*false" "${APPLY_WORKFLOW}"; then
    record_pass "Apply workflow concurrency configured with cancel-in-progress: false (state lock safety)"
else
    record_fail "Apply workflow cancel-in-progress must be strictly false"
fi

# ------------------------------------------------------------------------------
# Phase 4: Workload Identity Federation (WIF) & IAM Permissions
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 4: WIF Keyless Authentication & Permission Scopes...${RESET}"

# id-token: write permissions
if grep -qE "id-token:\s*write" "${PLAN_WORKFLOW}" && \
   grep -qE "id-token:\s*write" "${APPLY_WORKFLOW}"; then
    record_pass "OIDC id-token: write permission declared across both workflows"
else
    record_fail "Missing id-token: write permission in one or both workflows"
fi

# Keyless WIF auth action
if grep -qE "google-github-actions/auth" "${PLAN_WORKFLOW}" && \
   grep -qE "google-github-actions/auth" "${APPLY_WORKFLOW}"; then
    record_pass "Keyless google-github-actions/auth step present in both workflows"
else
    record_fail "Missing google-github-actions/auth step in workflows"
fi

# Zero static service account keys in IaC
SA_KEYS_COUNT=0
for tf in $(find "${WORKSPACE_ROOT}/terraform" -name "*.tf" 2>/dev/null); do
    if grep -qE 'resource\s+"google_service_account_key"' "$tf"; then
        SA_KEYS_COUNT=$((SA_KEYS_COUNT + 1))
    fi
done
if [[ ${SA_KEYS_COUNT} -eq 0 ]]; then
    record_pass "Zero static service account keys detected across all Terraform configurations"
else
    record_fail "Detected ${SA_KEYS_COUNT} static service account keys (security violation)"
fi

# ------------------------------------------------------------------------------
# Phase 5: CI/CD Quality Checks & Sticky PR Feedback
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 5: Workflow Step Quality & Execution Steps...${RESET}"

# Format check and schema validation
if grep -qE "terraform fmt" "${PLAN_WORKFLOW}" && \
   grep -qE "terraform validate" "${PLAN_WORKFLOW}"; then
    record_pass "Plan workflow includes terraform fmt check and terraform validate"
else
    record_fail "Missing terraform fmt or terraform validate in plan workflow"
fi

# Automated terraform plan and sticky comment
if grep -qE "terraform plan" "${PLAN_WORKFLOW}" && \
   grep -qE "sticky-pull-request-comment|github-script" "${PLAN_WORKFLOW}"; then
    record_pass "Plan workflow captures plan diagnostics and updates sticky PR comment"
else
    record_fail "Plan workflow missing terraform plan or sticky comment integration"
fi

# Automated terraform apply with auto-approve
if grep -qE "terraform apply[^\n]*-auto-approve" "${APPLY_WORKFLOW}"; then
    record_pass "Apply workflow executes automated terraform apply with -auto-approve"
else
    record_fail "Apply workflow missing terraform apply -auto-approve"
fi

# Post-apply verification check
if grep -qE "verify-workstation\.sh" "${APPLY_WORKFLOW}"; then
    record_pass "Apply workflow executes post-apply verification check"
else
    record_fail "Apply workflow missing verify-workstation.sh post-apply check"
fi

# ------------------------------------------------------------------------------
# Phase 6: Portfolio Documentation & Architectural Invariants
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 6: Portfolio README Standards & Technical Invariants...${RESET}"

# Balanced Markdown code fences
FENCE_COUNT=$(grep -c '^[~`][~`][~`]' "${README_FILE}" || echo 0)
if [[ $((FENCE_COUNT % 2)) -eq 0 ]]; then
    record_pass "Markdown code fences are balanced (${FENCE_COUNT} markers, 0 unclosed)"
else
    record_fail "Unbalanced Markdown code fences detected in README.md (${FENCE_COUNT} markers)"
fi

# Interactive Mermaid architecture diagram
if grep -qF '```mermaid' "${README_FILE}" && \
   grep -qE "flowchart TD|graph TD" "${README_FILE}"; then
    record_pass "Mermaid architecture diagram present with valid flowchart topology"
else
    record_fail "Missing or malformed Mermaid diagram in README.md"
fi

# Terminal-friendly ASCII network topology
if grep -qE "(\+---|┌───)" "${README_FILE}"; then
    record_pass "Terminal-friendly ASCII network topology diagram present"
else
    record_fail "Missing ASCII architecture diagram in README.md"
fi

# Zero-Trust network security model
if grep -qE "[Zz]ero-[Tt]rust" "${README_FILE}" && \
   grep -qE "41641" "${README_FILE}" && \
   grep -qE "35\.235\.240\.0/20" "${README_FILE}"; then
    record_pass "Zero-Trust security model documented (Tailscale WireGuard, IAP CIDR 35.235.240.0/20)"
else
    record_fail "Zero-Trust security section incomplete or missing"
fi

# Workload Identity Federation rationale
if grep -qE "Workload Identity Federation" "${README_FILE}" && \
   grep -qE "assertion\.repository" "${README_FILE}"; then
    record_pass "WIF keyless authentication mechanics and repository condition documented"
else
    record_fail "WIF rationale section incomplete or missing"
fi

# Financial right-sizing math ($24 vs $97)
if grep -qE "e2-medium" "${README_FILE}" && \
   grep -qE "(\$24|24\.46)" "${README_FILE}" && \
   grep -qE "(\$97|97\.10)" "${README_FILE}"; then
    record_pass 'Financial architecture math documented ($24/mo e2-medium vs $97/mo e2-standard-4)'
else
    record_fail "Financial architecture economics missing from README.md"
fi

# 4GB swapfile and Linux kernel memory tuning
if grep -qE "4GB [Ss]wapfile" "${README_FILE}" && \
   grep -qE "vm\.swappiness\s*=\s*10" "${README_FILE}" && \
   grep -qE "vm\.vfs_cache_pressure\s*=\s*50" "${README_FILE}"; then
    record_pass "Memory sizing math and kernel sysctl tuning documented (4GB swap, swappiness=10, vfs_cache_pressure=50)"
else
    record_fail "Swapfile and kernel memory tuning section missing or incomplete"
fi

# Prohibited internal agent strings scan
if ! grep -qiE "AI Agent|Teamwork agent|orchestrator_workstation" "${README_FILE}"; then
    record_pass "Zero prohibited internal agent strings found in public portfolio documentation"
else
    record_fail "Internal agent strings leaked into public README.md"
fi

# ------------------------------------------------------------------------------
# Phase 7: E2E Runner Test Suite Execution (--stage M3)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 7: Running E2E Test Suite for Stage M3...${RESET}"
E2E_RUNNER="${WORKSPACE_ROOT}/tests/e2e_runner.sh"
if [[ -f "${E2E_RUNNER}" ]]; then
    if "${E2E_RUNNER}" --stage M3; then
        record_pass "E2E runner completed with 100% pass rate for Stage M3"
    else
        record_fail "E2E runner reported test failures in Stage M3"
    fi
else
    record_fail "Missing tests/e2e_runner.sh harness"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}========================================================================${RESET}"
if [[ ${FAILURES} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}AUDIT SUCCESSFUL: 0 defects detected. Milestone 3 Certified.${RESET}"
    echo -e "${BOLD}========================================================================${RESET}"
    exit 0
else
    echo -e "${RED}${BOLD}AUDIT FAILED: ${FAILURES} defect(s) detected. Fix required.${RESET}"
    echo -e "${BOLD}========================================================================${RESET}"
    exit 1
fi
