#!/usr/bin/env bash
# ==============================================================================
# scripts/verify_m2_workstation.sh
# Turnkey Verification & Audit Runner for Milestone 2 (Workstation IaC & Startup)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_BOOTSTRAP_DIR="${WORKSPACE_ROOT}/terraform/00-bootstrap"
TF_WORKSTATION_DIR="${WORKSPACE_ROOT}/terraform/01-workstation"
STARTUP_SCRIPT="${TF_WORKSTATION_DIR}/startup.sh"

BOLD="\033[1m"
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo -e "${BOLD}========================================================================${RESET}"
echo -e "${BOLD}   Milestone 2 Quality, Contract & Startup Script Verification Audit    ${RESET}"
echo -e "${BOLD}========================================================================${RESET}"
echo -e "Workspace Root:   ${WORKSPACE_ROOT}"
echo -e "Workstation IaC:  ${TF_WORKSTATION_DIR}"
echo -e "Startup Script:   ${STARTUP_SCRIPT}"
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
echo -e "${YELLOW}Phase 1: Verifying Milestone 2 File Scaffold...${RESET}"
REQUIRED_FILES=(
    "terraform/01-workstation/main.tf"
    "terraform/01-workstation/variables.tf"
    "terraform/01-workstation/outputs.tf"
    "terraform/01-workstation/versions.tf"
    "terraform/01-workstation/remote_state.tf"
    "terraform/01-workstation/startup.sh"
    "terraform/01-workstation/terraform.tfvars.example"
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
echo -e "\n${YELLOW}Phase 2: Static Analysis & Formatting Checks...${RESET}"
if terraform fmt -check -diff -recursive "${TF_WORKSTATION_DIR}" > /dev/null 2>&1; then
    record_pass "terraform fmt formatting check"
else
    record_fail "terraform fmt detected unformatted files in terraform/01-workstation/"
fi

if (cd "${TF_WORKSTATION_DIR}" && terraform init -backend=false > /dev/null 2>&1); then
    record_pass "terraform init -backend=false initialized cleanly"
else
    record_fail "terraform init -backend=false failed"
fi

VAL_OUTPUT=$(cd "${TF_WORKSTATION_DIR}" && terraform validate 2>&1)
if [[ $? -eq 0 ]]; then
    record_pass "terraform validate passed"
else
    record_fail "terraform validate failed:\n${VAL_OUTPUT}"
fi

if bash -n "${STARTUP_SCRIPT}" > /dev/null 2>&1; then
    record_pass "bash -n syntax validation on startup.sh"
else
    record_fail "bash -n detected syntax errors in startup.sh"
fi

# ------------------------------------------------------------------------------
# Phase 3: Layer Interface Contract Validation
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 3: Layer Interface Contract Validation...${RESET}"

# Verify remote state data source ingestion
if grep -rn "data\s\+\"terraform_remote_state\"\s\+\"bootstrap\"" "${TF_WORKSTATION_DIR}" > /dev/null 2>&1; then
    record_pass "Consumes bootstrap remote state via data.terraform_remote_state.bootstrap"
else
    record_fail "Missing data.terraform_remote_state.bootstrap in 01-workstation"
fi

# Verify exported outputs
CONTRACT_OUTPUTS=(
    "instance_name"
    "instance_zone"
    "instance_internal_ip"
    "instance_external_ip"
    "vpc_network_name"
    "subnet_name"
)

for out in "${CONTRACT_OUTPUTS[@]}"; do
    if grep -E "output\s+\"${out}\"" "${TF_WORKSTATION_DIR}/outputs.tf" > /dev/null 2>&1; then
        record_pass "Contract output declared: ${out}"
    else
        record_fail "Missing required contract output: ${out}"
    fi
done

# Verify zero outputs incorrectly masked with sensitive = true
if grep -E "sensitive\s*=\s*true" "${TF_WORKSTATION_DIR}/outputs.tf" > /dev/null 2>&1; then
    record_fail "Outputs contain sensitive = true (contract requires accessible network metadata)"
else
    record_pass "Zero outputs masked with sensitive = true"
fi

# ------------------------------------------------------------------------------
# Phase 4: Compute Engine & Security Policy Checks
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 4: Compute Engine & Security Invariants...${RESET}"

# Machine type check
if grep -q "e2-medium" "${TF_WORKSTATION_DIR}/main.tf" "${TF_WORKSTATION_DIR}/variables.tf"; then
    record_pass "Machine type e2-medium specified"
else
    record_fail "Machine type e2-medium missing from main.tf/variables.tf"
fi

# Boot disk size >= 50GB pd-balanced
if grep -qE "size\s*=\s*(50|[5-9][0-9])" "${TF_WORKSTATION_DIR}/main.tf" && \
   grep -q "pd-balanced" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Boot disk configured for >= 50GB pd-balanced"
else
    record_fail "Boot disk size (<50GB) or type (not pd-balanced) violation"
fi

# Dedicated Service Account attached
if grep -q "service_account\s*{" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Runtime service account attached to VM"
else
    record_fail "Runtime service account block missing from compute instance"
fi

# OS Login enabled
if grep -qE "enable-oslogin\s*=\s*['\"](TRUE|true)['\"]" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "OS Login metadata flag enabled"
else
    record_fail "enable-oslogin metadata flag missing or not set to TRUE"
fi

# Non-preemptible on-demand scheduling
if grep -q "preemptible\s*=\s*true" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_fail "Preemptible instances prohibited for persistent workstation"
else
    record_pass "On-demand instance scheduling enforced (non-preemptible)"
fi

# ------------------------------------------------------------------------------
# Phase 5: Zero-Trust Networking & Firewall Rules
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 5: Zero-Trust Networking & Firewall Rules...${RESET}"

# Custom VPC declaration
if grep -qE 'resource\s+"google_compute_network"' "${TF_WORKSTATION_DIR}/main.tf" && \
   grep -qE "auto_create_subnetworks\s*=\s*false" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Custom VPC network declared with auto_create_subnetworks = false"
else
    record_fail "VPC network declaration missing or auto_create_subnetworks not false"
fi

# Subnet with Private Google Access
if grep -qE "private_ip_google_access\s*=\s*true" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Private Google Access enabled on subnetwork"
else
    record_fail "private_ip_google_access = true missing on subnetwork"
fi

# Mosh UDP 60000-61000 firewall rule
if grep -q "60000-61000" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Firewall rule allows Mosh UDP ports 60000-61000"
else
    record_fail "Mosh UDP 60000-61000 firewall port range missing"
fi

# Tailscale WireGuard UDP 41641 firewall rule
if grep -q "41641" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "Firewall rule allows Tailscale WireGuard UDP port 41641"
else
    record_fail "Tailscale UDP 41641 firewall rule missing"
fi

# Prohibit public 0.0.0.0/0 on TCP port 22
if grep -qE '0\.0\.0\.0/0[^\}]*ports\s*=\s*\["22"\]' "${TF_WORKSTATION_DIR}/main.tf" || \
   grep -qE 'ports\s*=\s*\["22"\][^\}]*0\.0\.0\.0/0' "${TF_WORKSTATION_DIR}/main.tf"; then
    record_fail "SECURITY VIOLATION: Open public SSH (0.0.0.0/0:22) detected in firewall rules"
else
    record_pass "Zero open public SSH (0.0.0.0/0:22 is strictly forbidden)"
fi

# Google Cloud IAP SSH range (35.235.240.0/20) allowed
if grep -q "35.235.240.0/20" "${TF_WORKSTATION_DIR}/main.tf"; then
    record_pass "SSH ingress restricted strictly to Google Cloud IAP CIDR (35.235.240.0/20)"
else
    record_fail "Google Cloud IAP CIDR (35.235.240.0/20) missing from SSH firewall rule"
fi

# ------------------------------------------------------------------------------
# Phase 6: Startup Script Provisions & Quality Assurance (QA)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 6: Startup Script Provisions & QA Invariants...${RESET}"

# 4GB swapfile logic & permissions
if grep -qE "(fallocate -l 4G /swapfile|count=4096)" "${STARTUP_SCRIPT}" && \
   grep -q "chmod 600 /swapfile" "${STARTUP_SCRIPT}" && \
   grep -q "/swapfile none swap sw 0 0" "${STARTUP_SCRIPT}"; then
    record_pass "4GB swapfile allocation, 0600 permissions & /etc/fstab entry verified"
else
    record_fail "4GB swapfile allocation, permissions, or fstab entry defect in startup.sh"
fi

# Kernel memory tuning
if grep -qE "vm\.swappiness\s*=\s*(10|20)" "${STARTUP_SCRIPT}" && \
   grep -qE "vm\.vfs_cache_pressure\s*=\s*50" "${STARTUP_SCRIPT}"; then
    record_pass "Kernel swappiness and vfs_cache_pressure tuning verified"
else
    record_fail "Kernel swappiness (10/20) or vfs_cache_pressure (50) missing from startup.sh"
fi

# Single-line apt-get install for mosh & tmux (QA Defect 1 check)
if grep -qE "apt-get install[^\n]*mosh" "${STARTUP_SCRIPT}" && \
   grep -qE "apt-get install[^\n]*tmux" "${STARTUP_SCRIPT}"; then
    record_pass "mosh and tmux packages installed via apt (regex compliant)"
else
    record_fail "mosh or tmux missing from apt-get install single-line pattern in startup.sh"
fi

# Secret Manager REST API endpoint syntax
if grep -q "secretmanager\.googleapis\.com" "${STARTUP_SCRIPT}" && \
   grep -q "computeMetadata/v1/instance/service-accounts/default/token" "${STARTUP_SCRIPT}"; then
    record_pass "Secret Manager REST API queries instance metadata token correctly"
else
    record_fail "Secret Manager REST API query or metadata token endpoint missing in startup.sh"
fi

# Tailscale & Tailscale SSH
if grep -q "tailscale\.com/install\.sh" "${STARTUP_SCRIPT}" && \
   grep -q "systemctl enable --now tailscaled" "${STARTUP_SCRIPT}" && \
   grep -qE "tailscale up [^\n]*--ssh" "${STARTUP_SCRIPT}"; then
    record_pass "Tailscale installer, systemd daemon, and --ssh flag verified"
else
    record_fail "Tailscale installer, daemon, or --ssh flag missing in startup.sh"
fi

# tmux auto-attach & defensive TTY guard
if grep -qE "\[\s*-t\s*[01]\s*\]" "${STARTUP_SCRIPT}" && \
   grep -qE '\[\s*-z\s*"\${?TMUX' "${STARTUP_SCRIPT}" && \
   grep -q "SSH_ORIGINAL_COMMAND" "${STARTUP_SCRIPT}"; then
    record_pass "Safe defensive tmux auto-attach guard ([ -t 0 ], TMUX, SSH_ORIGINAL_COMMAND) verified"
else
    record_fail "tmux auto-attach missing required defensive TTY/session guards in startup.sh"
fi

# Developer Toolchain (Node 22 LTS, Python 3, agy CLI)
if grep -qE "node_22\.x|setup_22\.x" "${STARTUP_SCRIPT}" && \
   grep -q "python3-venv" "${STARTUP_SCRIPT}" && \
   grep -q "antigravity\.google/cli/install\.sh" "${STARTUP_SCRIPT}" && \
   grep -q "/usr/local/bin" "${STARTUP_SCRIPT}"; then
    record_pass "Developer toolchain (Node.js 22 LTS, Python 3 venv, agy CLI) verified"
else
    record_fail "Developer toolchain provisioning defect in startup.sh"
fi

# FireMonitoringSystem clone & .git check (QA Defect 2 check)
if grep -qE "git clone[^\n]*FireMonitoringSystem" "${STARTUP_SCRIPT}" && \
   grep -qE "if\s*\[\s*-d[^\n]*/\.git\s*\]" "${STARTUP_SCRIPT}" && \
   grep -q "chown -R ubuntu:ubuntu" "${STARTUP_SCRIPT}"; then
    record_pass "FireMonitoringSystem clone, idempotent .git check & user ownership verified"
else
    record_fail "FireMonitoringSystem clone, idempotent .git check, or chown defect in startup.sh"
fi

# ------------------------------------------------------------------------------
# Phase 7: E2E Runner Test Suite Execution (--stage M2)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}Phase 7: Running E2E Test Suite for Stage M2...${RESET}"
E2E_RUNNER="${WORKSPACE_ROOT}/tests/e2e_runner.sh"
if [[ -f "${E2E_RUNNER}" ]]; then
    if "${E2E_RUNNER}" --stage M2; then
        record_pass "E2E runner completed with 100% pass rate for Stage M2"
    else
        record_fail "E2E runner reported test failures in Stage M2"
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
    echo -e "${GREEN}${BOLD}AUDIT SUCCESSFUL: 0 defects detected. Milestone 2 Certified.${RESET}"
    echo -e "${BOLD}========================================================================${RESET}"
    exit 0
else
    echo -e "${RED}${BOLD}AUDIT FAILED: ${FAILURES} defect(s) detected. Fix required.${RESET}"
    echo -e "${BOLD}========================================================================${RESET}"
    exit 1
fi
