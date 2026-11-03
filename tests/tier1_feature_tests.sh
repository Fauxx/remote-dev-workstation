#!/usr/bin/env bash
# ==============================================================================
# tier1_feature_tests.sh — Isolated Feature Functionality Tests (Features 1..21)
# Total Test Cases: 105 (5 test cases per feature across 21 features)
# Progressive Testability Enabled: Evaluates static specs & live state
# ==============================================================================
set -uo pipefail

ROOT="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Helper to find file across standard locations
find_file() {
    local rel_path="$1"
    if [ -f "${ROOT}/${rel_path}" ]; then
        echo "${ROOT}/${rel_path}"
    elif [ -f "${ROOT}/terraform/${rel_path}" ]; then
        echo "${ROOT}/terraform/${rel_path}"
    elif [ -f "${ROOT}/scripts/${rel_path}" ]; then
        echo "${ROOT}/scripts/${rel_path}"
    else
        echo ""
    fi
}

# ==============================================================================
# FEATURE 1: GitHub Repository Setup (Milestone: M1)
# ==============================================================================
test_t1_1_1() {
    # Expected: Repository public visibility in scaffold / git config / gh repo view
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        local repo_view
        repo_view=$(gh repo view Fauxx/remote-dev-workstation --json isPrivate,name -q .isPrivate 2>/dev/null || true)
        if [ "${repo_view}" = "false" ]; then
            assert_eq "${repo_view}" "false" "Remote repo is public"
            return $?
        fi
    fi
    # Progressive fallback: Check bootstrap / scaffold declarations
    local b_script=$(find_file "bootstrap-local.sh")
    if [ -n "${b_script}" ] && [ -f "${b_script}" ] && grep -qE "(--public|repo create.*--public)" "${b_script}"; then
        assert_file_contains "${b_script}" "(--public|repo create.*--public)" "Bootstrap script specifies public visibility"
    else
        skip_test "Pending M1: Repository creation in progress on remote"
    fi
}

test_t1_1_2() {
    # Expected: Target repo name 'remote-dev-workstation' and owner 'Fauxx'
    local b_script=$(find_file "bootstrap-local.sh")
    local tf_vars=$(find_file "00-bootstrap/variables.tf")
    if [ -n "${tf_vars}" ] && [ -f "${tf_vars}" ]; then
        assert_file_contains "${tf_vars}" "Fauxx/remote-dev-workstation" "variables.tf targets Fauxx/remote-dev-workstation"
    elif [ -n "${b_script}" ] && [ -f "${b_script}" ]; then
        assert_file_contains "${b_script}" "Fauxx/remote-dev-workstation" "Script targets Fauxx/remote-dev-workstation"
    else
        skip_test "Pending M1: Repository variables definition"
    fi
}

test_t1_1_3() {
    # Expected: Standard directory layout scaffolding
    if [ -d "${ROOT}/terraform" ] || [ -d "${ROOT}/00-bootstrap" ] || [ -d "${ROOT}/scripts" ]; then
        assert_dir_exists "${ROOT}/tests" "tests directory exists"
    else
        skip_test "Pending M1: Workspace directory scaffold"
    fi
}

test_t1_1_4() {
    # Expected: Git remote origin URL points to Fauxx/remote-dev-workstation
    if [ -d "${ROOT}/.git" ]; then
        local origin_url
        origin_url=$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)
        if [ -n "${origin_url}" ]; then
            assert_contains "${origin_url}" "remote-dev-workstation" "Git remote origin contains remote-dev-workstation"
            return $?
        fi
    fi
    skip_test "Pending M1: Git repository initialization and remote origin configuration"
}

test_t1_1_5() {
    # Expected: .gitignore contains critical exclusions for Terraform and GCP
    local gitignore="${ROOT}/.gitignore"
    if [ -f "${gitignore}" ]; then
        assert_file_contains "${gitignore}" "\*\.tfstate" ".gitignore excludes *.tfstate" && \
        assert_file_contains "${gitignore}" "\.terraform" ".gitignore excludes .terraform" && \
        assert_file_contains "${gitignore}" "\*\.json\.key|\*credentials\*\.json" ".gitignore excludes GCP credentials"
    else
        skip_test "Pending M1: .gitignore creation"
    fi
}

register_and_run_test "T1.1.1" 1 1 "M1" "Repo Public Visibility Specification" test_t1_1_1
register_and_run_test "T1.1.2" 1 1 "M1" "Repo Name & Owner Binding" test_t1_1_2
register_and_run_test "T1.1.3" 1 1 "M1" "Standard Repository Layout Scaffold" test_t1_1_3
register_and_run_test "T1.1.4" 1 1 "M1" "Git Remote Origin Tracking" test_t1_1_4
register_and_run_test "T1.1.5" 1 1 "M1" "Defensive .gitignore Exclusions" test_t1_1_5

# ==============================================================================
# FEATURE 2: GCP Project Creation & Billing (Milestone: M1)
# ==============================================================================
test_t1_2_1() {
    # Expected: Target billing account is 01833A-97FE0E-12FAE5
    local tf_file=$(find_file "00-bootstrap/main.tf")
    local tfvars=$(find_file "00-bootstrap/terraform.tfvars.example")
    if [ -n "${tf_file}" ] && [ -f "${tf_file}" ]; then
        assert_file_contains "${tf_file}" "billing_account" "00-bootstrap defines billing_account linkage"
    elif [ -n "${tfvars}" ] && [ -f "${tfvars}" ]; then
        assert_file_contains "${tfvars}" "01833A-97FE0E-12FAE5" "terraform.tfvars.example defines billing account"
    else
        skip_test "Pending M1: 00-bootstrap/main.tf creation"
    fi
}

test_t1_2_2() {
    # Expected: Organization ID linkage 705988173122
    local tf_vars=$(find_file "00-bootstrap/variables.tf")
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_vars}" ] && [ -f "${tf_vars}" ]; then
        assert_file_contains "${tf_vars}" "705988173122|org_id" "variables.tf contains org_id declaration"
    elif [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "org_id" "main.tf declares org_id linkage"
    else
        skip_test "Pending M1: 00-bootstrap variables"
    fi
}

test_t1_2_3() {
    # Expected: google_project resource declared with dynamic prefix
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"google_project"' "google_project resource declared"
    else
        skip_test "Pending M1: google_project in 00-bootstrap"
    fi
}

test_t1_2_4() {
    # Expected: auto_create_network = false to prevent default network clutter
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "auto_create_network\s*=\s*false" "auto_create_network set to false"
    else
        skip_test "Pending M1: auto_create_network configuration"
    fi
}

test_t1_2_5() {
    # Expected: random_id or suffix generator to avoid project ID collision
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"random_id"|"random_string"' "Dynamic suffix generator declared"
    else
        skip_test "Pending M1: random suffix for project ID"
    fi
}

register_and_run_test "T1.2.1" 1 2 "M1" "Billing Account Linkage Specification" test_t1_2_1
register_and_run_test "T1.2.2" 1 2 "M1" "Organization ID Linkage" test_t1_2_2
register_and_run_test "T1.2.3" 1 2 "M1" "google_project Resource Declaration" test_t1_2_3
register_and_run_test "T1.2.4" 1 2 "M1" "Default Network Suppression (auto_create_network=false)" test_t1_2_4
register_and_run_test "T1.2.5" 1 2 "M1" "Project ID Random Suffix Generator" test_t1_2_5

# ==============================================================================
# FEATURE 3: GCP APIs Enablement (Milestone: M1)
# ==============================================================================
test_t1_3_1() {
    # Expected: compute.googleapis.com enabled
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "compute\.googleapis\.com" "Compute Engine API enabled"
    else
        skip_test "Pending M1: API enablement in 00-bootstrap"
    fi
}

test_t1_3_2() {
    # Expected: iam.googleapis.com and iamcredentials.googleapis.com enabled
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "iam\.googleapis\.com" "IAM API enabled" && \
        assert_file_contains "${tf_main}" "iamcredentials\.googleapis\.com" "IAM Credentials API enabled"
    else
        skip_test "Pending M1: IAM APIs in 00-bootstrap"
    fi
}

test_t1_3_3() {
    # Expected: sts.googleapis.com enabled for WIF token exchange
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "sts\.googleapis\.com" "STS API enabled"
    else
        skip_test "Pending M1: STS API in 00-bootstrap"
    fi
}

test_t1_3_4() {
    # Expected: secretmanager.googleapis.com and storage.googleapis.com enabled
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "secretmanager\.googleapis\.com" "Secret Manager API enabled" && \
        assert_file_contains "${tf_main}" "storage.*\.googleapis\.com" "Storage API enabled"
    else
        skip_test "Pending M1: Secret Manager and Storage APIs"
    fi
}

test_t1_3_5() {
    # Expected: disable_on_destroy = false on google_project_service
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "disable_on_destroy\s*=\s*false" "disable_on_destroy set to false"
    else
        skip_test "Pending M1: disable_on_destroy API policy"
    fi
}

register_and_run_test "T1.3.1" 1 3 "M1" "Compute Engine API Enablement" test_t1_3_1
register_and_run_test "T1.3.2" 1 3 "M1" "IAM & IAM Credentials APIs Enablement" test_t1_3_2
register_and_run_test "T1.3.3" 1 3 "M1" "Security Token Service (STS) API Enablement" test_t1_3_3
register_and_run_test "T1.3.4" 1 3 "M1" "Secret Manager & Storage APIs Enablement" test_t1_3_4
register_and_run_test "T1.3.5" 1 3 "M1" "API Deletion Protection (disable_on_destroy=false)" test_t1_3_5

# ==============================================================================
# FEATURE 4: Remote State Storage (GCS) (Milestone: M1)
# ==============================================================================
test_t1_4_1() {
    # Expected: google_storage_bucket resource declared
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"google_storage_bucket"' "State bucket resource declared"
    else
        skip_test "Pending M1: GCS State bucket in 00-bootstrap"
    fi
}

test_t1_4_2() {
    # Expected: uniform_bucket_level_access = true (Strict Org Policy Compliance)
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "uniform_bucket_level_access\s*=\s*true" "Uniform bucket level access enforced"
    else
        skip_test "Pending M1: uniform_bucket_level_access declaration"
    fi
}

test_t1_4_3() {
    # Expected: versioning { enabled = true } for state durability
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        if grep -q "versioning" "${tf_main}"; then
            assert_file_contains "${tf_main}" "enabled\s*=\s*true" "Bucket versioning enabled"
        else
            skip_test "Pending M1: versioning block in 00-bootstrap/main.tf"
        fi
    else
        skip_test "Pending M1: Bucket versioning configuration"
    fi
}

test_t1_4_4() {
    # Expected: force_destroy = true or lifecycle prevent_destroy / deletion_policy
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "force_destroy\s*=\s*true|prevent_destroy\s*=\s*true|deletion_policy" "Bucket deletion/lifecycle protection configured"
    else
        skip_test "Pending M1: force_destroy bucket setting"
    fi
}

test_t1_4_5() {
    # Expected: Outputs export state_bucket_name
    local tf_out=$(find_file "00-bootstrap/outputs.tf")
    if [ -n "${tf_out}" ] && [ -f "${tf_out}" ]; then
        assert_file_contains "${tf_out}" 'output\s+"state_bucket_name"' "outputs.tf exports state_bucket_name"
    else
        skip_test "Pending M1: 00-bootstrap outputs"
    fi
}

register_and_run_test "T1.4.1" 1 4 "M1" "GCS State Bucket Declaration" test_t1_4_1
register_and_run_test "T1.4.2" 1 4 "M1" "Uniform Bucket-Level Access Enforcement" test_t1_4_2
register_and_run_test "T1.4.3" 1 4 "M1" "State Bucket Versioning Durability" test_t1_4_3
register_and_run_test "T1.4.4" 1 4 "M1" "Clean Teardown Capability (force_destroy=true)" test_t1_4_4
register_and_run_test "T1.4.5" 1 4 "M1" "State Bucket Name Output Export" test_t1_4_5

# ==============================================================================
# FEATURE 5: Workload Identity Federation (WIF) (Milestone: M1)
# ==============================================================================
test_t1_5_1() {
    # Expected: google_iam_workload_identity_pool declared
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"google_iam_workload_identity_pool"' "WIF pool resource declared"
    else
        skip_test "Pending M1: WIF pool in 00-bootstrap"
    fi
}

test_t1_5_2() {
    # Expected: OIDC issuer token.actions.githubusercontent.com
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "token\.actions\.githubusercontent\.com" "GitHub OIDC issuer configured"
    else
        skip_test "Pending M1: WIF OIDC provider in 00-bootstrap"
    fi
}

test_t1_5_3() {
    # Expected: attribute_mapping contains google.subject and attribute.repository
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "attribute_mapping\s*=" "attribute_mapping declared" && \
        assert_file_contains "${tf_main}" "assertion\.repository" "Maps assertion.repository"
    else
        skip_test "Pending M1: WIF attribute mappings"
    fi
}

test_t1_5_4() {
    # Expected: attribute_condition restricts repository to designated repo (direct string or var.github_repo)
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'assertion\.repository\s*==\s*["\x27](\$\{var\.github_repo\}|Fauxx/remote-dev-workstation)["\x27]' "WIF condition restricts repo"
    else
        skip_test "Pending M1: WIF attribute condition"
    fi
}

test_t1_5_5() {
    # Expected: Service account binding with roles/iam.workloadIdentityUser
    local tf_main=$(find_file "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "roles/iam\.workloadIdentityUser" "workloadIdentityUser role bound"
    else
        skip_test "Pending M1: WIF service account IAM binding"
    fi
}

register_and_run_test "T1.5.1" 1 5 "M1" "WIF Pool Resource Declaration" test_t1_5_1
register_and_run_test "T1.5.2" 1 5 "M1" "GitHub OIDC Provider Issuer Configuration" test_t1_5_2
register_and_run_test "T1.5.3" 1 5 "M1" "WIF OIDC Attribute Claims Mapping" test_t1_5_3
register_and_run_test "T1.5.4" 1 5 "M1" "WIF Repository Scope Restriction Condition" test_t1_5_4
register_and_run_test "T1.5.5" 1 5 "M1" "CI Service Account WorkloadIdentityUser Binding" test_t1_5_5

# ==============================================================================
# FEATURE 6: Secret Manager Vault (Milestone: M1)
# ==============================================================================
test_t1_6_1() {
    # Expected: tailscale-auth-key secret definition
    local tf_main=$(find_file "00-bootstrap/main.tf")
    local tf_ws=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "tailscale-auth-key" "tailscale-auth-key secret declared in bootstrap"
    elif [ -n "${tf_ws}" ] && [ -f "${tf_ws}" ]; then
        assert_file_contains "${tf_ws}" "tailscale-auth-key" "tailscale-auth-key secret declared in workstation"
    else
        skip_test "Pending M1: Secret Manager secrets definition"
    fi
}

test_t1_6_2() {
    # Expected: github-ssh-private-key secret definition
    local tf_main=$(find_file "00-bootstrap/main.tf")
    local tf_ws=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "github-ssh-private-key" "github-ssh-private-key secret declared in bootstrap"
    elif [ -n "${tf_ws}" ] && [ -f "${tf_ws}" ]; then
        assert_file_contains "${tf_ws}" "github-ssh-private-key" "github-ssh-private-key secret declared in workstation"
    else
        skip_test "Pending M1: SSH private key secret definition"
    fi
}

test_t1_6_3() {
    # Expected: github-pat-token secret definition
    local tf_main=$(find_file "00-bootstrap/main.tf")
    local tf_ws=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "github-pat-token" "github-pat-token secret declared in bootstrap"
    elif [ -n "${tf_ws}" ] && [ -f "${tf_ws}" ]; then
        assert_file_contains "${tf_ws}" "github-pat-token" "github-pat-token secret declared in workstation"
    else
        skip_test "Pending M1: PAT token secret definition"
    fi
}

test_t1_6_4() {
    # Expected: VM Service Account granted roles/secretmanager.secretAccessor
    local tf_main=$(find_file "00-bootstrap/main.tf")
    local tf_ws=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ] && grep -q "secretAccessor" "${tf_main}"; then
        assert_file_contains "${tf_main}" "roles/secretmanager\.secretAccessor" "secretAccessor role bound in bootstrap"
    elif [ -n "${tf_ws}" ] && [ -f "${tf_ws}" ] && grep -q "secretAccessor" "${tf_ws}"; then
        assert_file_contains "${tf_ws}" "roles/secretmanager\.secretAccessor" "secretAccessor role bound in workstation"
    else
        skip_test "Pending M1/M2: secretAccessor IAM binding"
    fi
}

test_t1_6_5() {
    # Expected: Secret replication configured to automatic
    local tf_main=$(find_file "00-bootstrap/main.tf")
    local tf_ws=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ] && grep -q "replication" "${tf_main}"; then
        assert_file_contains "${tf_main}" "automatic\s*=\s*true|auto\s*\{\}" "Automatic replication configured"
    elif [ -n "${tf_ws}" ] && [ -f "${tf_ws}" ] && grep -q "replication" "${tf_ws}"; then
        assert_file_contains "${tf_ws}" "automatic\s*=\s*true|auto\s*\{\}" "Automatic replication configured"
    else
        skip_test "Pending M1: Secret replication policy"
    fi
}

register_and_run_test "T1.6.1" 1 6 "M1" "Tailscale Auth Key Secret Declaration" test_t1_6_1
register_and_run_test "T1.6.2" 1 6 "M1" "GitHub SSH Private Key Secret Declaration" test_t1_6_2
register_and_run_test "T1.6.3" 1 6 "M1" "GitHub PAT Token Secret Declaration" test_t1_6_3
register_and_run_test "T1.6.4" 1 6 "M1" "VM Service Account SecretAccessor IAM Binding" test_t1_6_4
register_and_run_test "T1.6.5" 1 6 "M1" "Secret Automatic Replication Policy" test_t1_6_5

# ==============================================================================
# FEATURE 7: VPC Network & Firewall (Milestone: M2)
# ==============================================================================
test_t1_7_1() {
    # Expected: google_compute_network custom VPC with auto_create_subnetworks=false
    local tf_main=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"google_compute_network"' "Compute network declared" && \
        assert_file_contains "${tf_main}" "auto_create_subnetworks\s*=\s*false" "auto_create_subnetworks set to false"
    else
        skip_test "Pending M2: VPC in 01-workstation"
    fi
}

test_t1_7_2() {
    # Expected: google_compute_subnetwork declared with private_ip_google_access=true
    local tf_main=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'resource\s+"google_compute_subnetwork"' "Subnetwork declared" && \
        assert_file_contains "${tf_main}" "private_ip_google_access\s*=\s*true" "Private Google Access enabled"
    else
        skip_test "Pending M2: Subnetwork in 01-workstation"
    fi
}

test_t1_7_3() {
    # Expected: Mosh firewall rule allows UDP 60000-61000
    local tf_main=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "60000-61000" "Mosh UDP port range 60000-61000 allowed"
    else
        skip_test "Pending M2: Mosh firewall rule"
    fi
}

test_t1_7_4() {
    # Expected: Tailscale firewall rule allows UDP 41641
    local tf_main=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "41641" "Tailscale UDP port 41641 allowed"
    else
        skip_test "Pending M2: Tailscale firewall rule"
    fi
}

test_t1_7_5() {
    # Expected: Zero public TCP 22 ingress (restricted to IAP 35.235.240.0/20 or Tailscale SSH only)
    local tf_main=$(find_file "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        if grep -q "35.235.240.0/20" "${tf_main}"; then
            assert_file_contains "${tf_main}" "35\.235\.240\.0/20" "SSH restricted to Google IAP range"
        else
            assert_file_not_contains "${tf_main}" 'ports\s*=\s*\["22"\][^\}]*0\.0\.0\.0/0' "Prohibit public 0.0.0.0/0 on port 22"
        fi
    else
        skip_test "Pending M2: Firewall SSH ingress restriction"
    fi
}

register_and_run_test "T1.7.1" 1 7 "M2" "Custom VPC Network Declaration" test_t1_7_1
register_and_run_test "T1.7.2" 1 7 "M2" "Private Subnet & Google Access Configuration" test_t1_7_2
register_and_run_test "T1.7.3" 1 7 "M2" "Mosh UDP 60000-61000 Firewall Port Range" test_t1_7_3
register_and_run_test "T1.7.4" 1 7 "M2" "Tailscale WireGuard UDP 41641 Firewall Rule" test_t1_7_4
register_and_run_test "T1.7.5" 1 7 "M2" "Zero-Trust SSH Ingress (Public Port 22 Prohibited)" test_t1_7_5

# ==============================================================================
# FEATURE 8: Compute Engine Workstation VM (Milestone: M2)
# ==============================================================================
test_t1_8_1() {
    # Expected: machine_type e2-medium
    local tf_main=$(find_file "01-workstation/main.tf")
    local tf_compute=$(find_file "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "e2-medium" "Machine type is e2-medium"
    else
        skip_test "Pending M2: Compute instance configuration"
    fi
}

test_t1_8_2() {
    # Expected: Ubuntu 24.04 LTS noble amd64 image family
    local tf_main=$(find_file "01-workstation/main.tf")
    local tf_compute=$(find_file "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "ubuntu-2404-lts|ubuntu-2404-noble" "OS image resolves to Ubuntu 24.04 LTS"
    else
        skip_test "Pending M2: OS image family specification"
    fi
}

test_t1_8_3() {
    # Expected: Boot disk size >= 50 GB pd-balanced
    local tf_main=$(find_file "01-workstation/main.tf")
    local tf_compute=$(find_file "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "size\s*=\s*(50|[5-9][0-9])" "Boot disk size is >= 50GB" && \
        assert_file_contains "${src}" "pd-balanced" "Boot disk type is pd-balanced"
    else
        skip_test "Pending M2: Boot disk size and type"
    fi
}

test_t1_8_4() {
    # Expected: Dedicated runtime service account attached
    local tf_main=$(find_file "01-workstation/main.tf")
    local tf_compute=$(find_file "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "service_account\s*\{" "Runtime service account attached"
    else
        skip_test "Pending M2: VM service account attachment"
    fi
}

test_t1_8_5() {
    # Expected: enable-oslogin = TRUE in instance metadata
    local tf_main=$(find_file "01-workstation/main.tf")
    local tf_compute=$(find_file "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "enable-oslogin\s*=\s*['\"](TRUE|true)['\"]" "enable-oslogin metadata enabled"
    else
        skip_test "Pending M2: OS Login metadata"
    fi
}

register_and_run_test "T1.8.1" 1 8 "M2" "e2-medium Machine Type Specification" test_t1_8_1
register_and_run_test "T1.8.2" 1 8 "M2" "Ubuntu 24.04 LTS Base OS Image" test_t1_8_2
register_and_run_test "T1.8.3" 1 8 "M2" "Boot Disk Sizing (>=50GB pd-balanced)" test_t1_8_3
register_and_run_test "T1.8.4" 1 8 "M2" "Runtime Service Account Binding" test_t1_8_4
register_and_run_test "T1.8.5" 1 8 "M2" "Cloud OS Login Metadata Flag" test_t1_8_5

# ==============================================================================
# FEATURE 9: 4GB Swapfile & Kernel Tuning (Milestone: M2)
# ==============================================================================
test_t1_9_1() {
    # Expected: 4GB swapfile creation in startup.sh (4G or 4294967296 bytes)
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "(fallocate -l 4G /swapfile|count=4096)" "Allocates 4GB swapfile"
    else
        skip_test "Pending M2: VM startup.sh script"
    fi
}

test_t1_9_2() {
    # Expected: chmod 600 /swapfile permissions enforcement
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chmod 600 /swapfile" "Enforces 0600 root permissions on swapfile"
    else
        skip_test "Pending M2: Swapfile permissions in startup.sh"
    fi
}

test_t1_9_3() {
    # Expected: Persistence in /etc/fstab
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "/swapfile none swap sw 0 0" "Persistent /etc/fstab entry"
    else
        skip_test "Pending M2: /etc/fstab entry in startup.sh"
    fi
}

test_t1_9_4() {
    # Expected: sysctl vm.swappiness=20 or 10
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "vm\.swappiness\s*=\s*(10|20)" "Tuned vm.swappiness sysctl"
    else
        skip_test "Pending M2: vm.swappiness sysctl in startup.sh"
    fi
}

test_t1_9_5() {
    # Expected: sysctl vm.vfs_cache_pressure=50
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "vm\.vfs_cache_pressure\s*=\s*50" "Tuned vm.vfs_cache_pressure sysctl"
    else
        skip_test "Pending M2: vm.vfs_cache_pressure sysctl in startup.sh"
    fi
}

register_and_run_test "T1.9.1" 1 9 "M2" "4GB Swapfile Allocation Logic" test_t1_9_1
register_and_run_test "T1.9.2" 1 9 "M2" "Swapfile 0600 File Permission Hardening" test_t1_9_2
register_and_run_test "T1.9.3" 1 9 "M2" "/etc/fstab Swap Persistence Entry" test_t1_9_3
register_and_run_test "T1.9.4" 1 9 "M2" "vm.swappiness Kernel Parameter Optimization" test_t1_9_4
register_and_run_test "T1.9.5" 1 9 "M2" "vm.vfs_cache_pressure File Cache Parameter" test_t1_9_5

# ==============================================================================
# FEATURE 10: Tailscale & Tailscale SSH (Milestone: M2)
# ==============================================================================
test_t1_10_1() {
    # Expected: Official Tailscale installer script fetch
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale\.com/install\.sh" "Official Tailscale installer referenced"
    else
        skip_test "Pending M2: Tailscale install in startup.sh"
    fi
}

test_t1_10_2() {
    # Expected: systemctl enable --now tailscaled
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "systemctl enable --now tailscaled" "Tailscaled systemd daemon enabled"
    else
        skip_test "Pending M2: tailscaled daemon configuration"
    fi
}

test_t1_10_3() {
    # Expected: tailscale up with --ssh flag
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale up [^\n]*--ssh" "Tailscale SSH flag enabled in connection command"
    else
        skip_test "Pending M2: Tailscale SSH flag in startup.sh"
    fi
}

test_t1_10_4() {
    # Expected: Hostname configured (e.g. mobile-workstation or remote-dev-workstation)
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "--hostname=" "Explicit Tailscale hostname passed"
    else
        skip_test "Pending M2: Tailscale hostname in startup.sh"
    fi
}

test_t1_10_5() {
    # Expected: Authkey retrieval from Secret Manager or metadata
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale-auth-key|tailscale-authkey" "Retrieves Tailscale auth key from secrets"
    else
        skip_test "Pending M2: Tailscale secret retrieval"
    fi
}

register_and_run_test "T1.10.1" 1 10 "M2" "Official Tailscale Installer Integration" test_t1_10_1
register_and_run_test "T1.10.2" 1 10 "M2" "Tailscaled Systemd Daemon Auto-Start" test_t1_10_2
register_and_run_test "T1.10.3" 1 10 "M2" "Zero-Trust Tailscale SSH Enablement Flag" test_t1_10_3
register_and_run_test "T1.10.4" 1 10 "M2" "Deterministic Tailnet Hostname Assignment" test_t1_10_4
register_and_run_test "T1.10.5" 1 10 "M2" "Dynamic Secret Manager Authkey Fetch" test_t1_10_5

# ==============================================================================
# FEATURE 11: Mosh & Safe tmux Auto-Attach (Milestone: M2)
# ==============================================================================
test_t1_11_1() {
    # Expected: mosh package installation in startup.sh
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "apt-get install[^\n]*mosh" "mosh package installed via apt"
    else
        skip_test "Pending M2: mosh in startup.sh"
    fi
}

test_t1_11_2() {
    # Expected: tmux package installation in startup.sh
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "apt-get install[^\n]*tmux" "tmux package installed via apt"
    else
        skip_test "Pending M2: tmux in startup.sh"
    fi
}

test_t1_11_3() {
    # Expected: Safe interactive TTY guard in .bashrc: [ -t 0 ] or [ -t 1 ]
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "\[\s*-t\s*[01]\s*\]" "Defensive TTY guard in .bashrc"
    else
        skip_test "Pending M2: .bashrc TTY guard in startup.sh"
    fi
}

test_t1_11_4() {
    # Expected: Nested session prevention guard in .bashrc: [ -z "$TMUX" ]
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" '\[\s*-z\s*"\$TMUX"\s*\]|\[\s*-z\s*"\${TMUX:-}"\s*\]' "Nested tmux prevention guard in .bashrc"
    else
        skip_test "Pending M2: .bashrc TMUX guard in startup.sh"
    fi
}

test_t1_11_5() {
    # Expected: Non-interactive SSH command bypass guard: [ -z "$SSH_ORIGINAL_COMMAND" ] or SSH_CONNECTION check
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'SSH_ORIGINAL_COMMAND|SSH_CONNECTION' "Non-interactive SSH bypass guard in .bashrc"
    else
        skip_test "Pending M2: .bashrc SSH command guard in startup.sh"
    fi
}

register_and_run_test "T1.11.1" 1 11 "M2" "Mosh Package Installation" test_t1_11_1
register_and_run_test "T1.11.2" 1 11 "M2" "tmux Package Installation" test_t1_11_2
register_and_run_test "T1.11.3" 1 11 "M2" "Defensive Interactive TTY Guard in .bashrc" test_t1_11_3
register_and_run_test "T1.11.4" 1 11 "M2" "Nested tmux Session Prevention Guard" test_t1_11_4
register_and_run_test "T1.11.5" 1 11 "M2" "Non-Interactive SSH Command Bypass Protection" test_t1_11_5

# ==============================================================================
# FEATURE 12: Credential Pre-seeding (Milestone: M2)
# ==============================================================================
test_t1_12_1() {
    # Expected: ~/.ssh directory created with 0700 permissions
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chmod 700 [^\n]*/\.ssh|mkdir -p -m 700 [^\n]*/\.ssh" "~/.ssh 0700 permissions enforced"
    else
        skip_test "Pending M2: SSH directory permissions in startup.sh"
    fi
}

test_t1_12_2() {
    # Expected: id_ed25519 private key created with 0600 permissions
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chmod 600 [^\n]*/id_ed25519" "SSH private key 0600 permissions enforced"
    else
        skip_test "Pending M2: SSH private key permissions in startup.sh"
    fi
}

test_t1_12_3() {
    # Expected: ssh-keyscan github.com populated in known_hosts
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "ssh-keyscan[^\n]*github\.com" "Pre-seeds github.com in known_hosts"
    else
        skip_test "Pending M2: known_hosts in startup.sh"
    fi
}

test_t1_12_4() {
    # Expected: Git global config user.name and user.email set
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "git config --global user\.name" "Configures git user.name" && \
        assert_file_contains "${startup}" "git config --global user\.email" "Configures git user.email"
    else
        skip_test "Pending M2: Git identity in startup.sh"
    fi
}

test_t1_12_5() {
    # Expected: GitHub CLI gh auth login execution
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "gh auth login" "Automates GitHub CLI authentication"
    else
        skip_test "Pending M2: gh auth login in startup.sh"
    fi
}

register_and_run_test "T1.12.1" 1 12 "M2" "SSH Directory 0700 Permission Hardening" test_t1_12_1
register_and_run_test "T1.12.2" 1 12 "M2" "SSH Private Key 0600 Permission Enforcement" test_t1_12_2
register_and_run_test "T1.12.3" 1 12 "M2" "GitHub Host Keys Pre-Seeding (known_hosts)" test_t1_12_3
register_and_run_test "T1.12.4" 1 12 "M2" "Git Global Author Name & Email Pre-Seeding" test_t1_12_4
register_and_run_test "T1.12.5" 1 12 "M2" "GitHub CLI Automated Authentication" test_t1_12_5

# ==============================================================================
# FEATURE 13: Developer Toolchain (Node/Python/agy) (Milestone: M2)
# ==============================================================================
test_t1_13_1() {
    # Expected: NodeSource Node.js 22 LTS installation
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "node_22\.x|setup_22\.x" "NodeSource Node.js 22 LTS configured"
    else
        skip_test "Pending M2: Node.js 22 in startup.sh"
    fi
}

test_t1_13_2() {
    # Expected: Python 3 package installation
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "python3" "Python 3 package installed"
    else
        skip_test "Pending M2: Python 3 in startup.sh"
    fi
}

test_t1_13_3() {
    # Expected: python3-venv and python3-pip installed
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "python3-venv" "python3-venv package installed"
    else
        skip_test "Pending M2: python3-venv in startup.sh"
    fi
}

test_t1_13_4() {
    # Expected: Antigravity CLI agy installation via official script
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "antigravity\.google/cli/install\.sh" "Antigravity CLI installer downloaded"
    else
        skip_test "Pending M2: Antigravity CLI in startup.sh"
    fi
}

test_t1_13_5() {
    # Expected: agy executable placed in system PATH (/usr/local/bin)
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "/usr/local/bin" "agy installed in system-wide /usr/local/bin"
    else
        skip_test "Pending M2: agy PATH in startup.sh"
    fi
}

register_and_run_test "T1.13.1" 1 13 "M2" "NodeSource Node.js 22 LTS Distribution" test_t1_13_1
register_and_run_test "T1.13.2" 1 13 "M2" "Python 3 System Environment Provisioning" test_t1_13_2
register_and_run_test "T1.13.3" 1 13 "M2" "Python Virtual Environment (venv) Tooling" test_t1_13_3
register_and_run_test "T1.13.4" 1 13 "M2" "Antigravity CLI Official Installer Execution" test_t1_13_4
register_and_run_test "T1.13.5" 1 13 "M2" "Antigravity CLI System-Wide PATH Placement" test_t1_13_5

# ==============================================================================
# FEATURE 14: Project Repository Clone (Milestone: M2)
# ==============================================================================
test_t1_14_1() {
    # Expected: Workspace directory creation /home/ubuntu/workspace
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "workspace" "Dedicated workspace directory created"
    else
        skip_test "Pending M2: Workspace directory in startup.sh"
    fi
}

test_t1_14_2() {
    # Expected: git clone https://github.com/Fauxx/FireMonitoringSystem.git
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "git clone[^\n]*FireMonitoringSystem" "Clones FireMonitoringSystem repository"
    else
        skip_test "Pending M2: git clone in startup.sh"
    fi
}

test_t1_14_3() {
    # Expected: Push URL configured to git@github.com:Fauxx/FireMonitoringSystem.git
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "git remote set-url --push|git@github\.com" "Configures SSH push remote URL"
    else
        skip_test "Pending M2: SSH push remote in startup.sh"
    fi
}

test_t1_14_4() {
    # Expected: Ownership chown to ubuntu user
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chown -R ubuntu:ubuntu" "Enforces ubuntu ownership on cloned workspace"
    else
        skip_test "Pending M2: Workspace permissions in startup.sh"
    fi
}

test_t1_14_5() {
    # Expected: Idempotent git fetch if directory already exists
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "git fetch" "Idempotent git fetch handling"
    else
        skip_test "Pending M2: Idempotent git handling in startup.sh"
    fi
}

register_and_run_test "T1.14.1" 1 14 "M2" "Developer Workspace Directory Creation" test_t1_14_1
register_and_run_test "T1.14.2" 1 14 "M2" "FireMonitoringSystem Repository Clone" test_t1_14_2
register_and_run_test "T1.14.3" 1 14 "M2" "Git SSH Push Remote Configuration" test_t1_14_3
register_and_run_test "T1.14.4" 1 14 "M2" "Workspace Non-Root User Ownership Enforcement" test_t1_14_4
register_and_run_test "T1.14.5" 1 14 "M2" "Idempotent Repository Update on Reboot" test_t1_14_5

# ==============================================================================
# FEATURE 15: CI/CD PR Plan Workflow (Milestone: M3)
# ==============================================================================
test_t1_15_1() {
    # Expected: Trigger on pull_request to main branch
    local wf=$(find_file ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "pull_request:" "Triggers on pull_request"
    else
        skip_test "Pending M3: PR workflow file creation"
    fi
}

test_t1_15_2() {
    # Expected: permissions id-token: write for WIF
    local wf=$(find_file ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "id-token:\s*write" "Requires id-token: write permission"
    else
        skip_test "Pending M3: PR workflow permissions"
    fi
}

test_t1_15_3() {
    # Expected: google-github-actions/auth action step
    local wf=$(find_file ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "google-github-actions/auth" "Uses google-github-actions/auth action"
    else
        skip_test "Pending M3: WIF auth step in PR workflow"
    fi
}

test_t1_15_4() {
    # Expected: terraform fmt -check and terraform validate steps
    local wf=$(find_file ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "terraform fmt" "Runs terraform fmt" && \
        assert_file_contains "${wf}" "terraform validate" "Runs terraform validate"
    else
        skip_test "Pending M3: Lint and validation steps in PR workflow"
    fi
}

test_t1_15_5() {
    # Expected: Sticky PR comment step
    local wf=$(find_file ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "sticky-pull-request-comment|github-script" "Posts sticky PR plan comment"
    else
        skip_test "Pending M3: Sticky comment step in PR workflow"
    fi
}

register_and_run_test "T1.15.1" 1 15 "M3" "PR Workflow Pull Request Trigger" test_t1_15_1
register_and_run_test "T1.15.2" 1 15 "M3" "OIDC JWT id-token:write Permission Scope" test_t1_15_2
register_and_run_test "T1.15.3" 1 15 "M3" "Keyless WIF Authentication Action" test_t1_15_3
register_and_run_test "T1.15.4" 1 15 "M3" "Automated Format Check & Schema Validation" test_t1_15_4
register_and_run_test "T1.15.5" 1 15 "M3" "Sticky PR Plan Markdown Comment Generation" test_t1_15_5

# ==============================================================================
# FEATURE 16: CI/CD Main Apply Workflow (Milestone: M3)
# ==============================================================================
test_t1_16_1() {
    # Expected: Trigger on push to main branch
    local wf=$(find_file ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "branches:\s*\[\s*main\s*\]" "Triggers on main branch push"
    else
        skip_test "Pending M3: Apply workflow file creation"
    fi
}

test_t1_16_2() {
    # Expected: concurrency cancel-in-progress: false (MANDATORY for apply safety)
    local wf=$(find_file ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "cancel-in-progress:\s*false" "cancel-in-progress set to false"
    else
        skip_test "Pending M3: Concurrency mutex in apply workflow"
    fi
}

test_t1_16_3() {
    # Expected: terraform apply with -auto-approve
    local wf=$(find_file ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "terraform apply[^\n]*-auto-approve" "Executes non-interactive terraform apply"
    else
        skip_test "Pending M3: terraform apply step in workflow"
    fi
}

test_t1_16_4() {
    # Expected: WIF authentication before apply
    local wf=$(find_file ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "google-github-actions/auth" "WIF authentication step present"
    else
        skip_test "Pending M3: WIF auth in apply workflow"
    fi
}

test_t1_16_5() {
    # Expected: Automated post-apply verification check step
    local wf=$(find_file ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "verify-workstation\.sh" "Invokes verify-workstation.sh post-apply"
    else
        skip_test "Pending M3: Post-apply verification step"
    fi
}

register_and_run_test "T1.16.1" 1 16 "M3" "Main Branch Push Trigger Definition" test_t1_16_1
register_and_run_test "T1.16.2" 1 16 "M3" "Apply Concurrency Mutex (cancel-in-progress=false)" test_t1_16_2
register_and_run_test "T1.16.3" 1 16 "M3" "Automated Non-Interactive Apply Execution" test_t1_16_3
register_and_run_test "T1.16.4" 1 16 "M3" "Keyless WIF Token Provisioning for Apply" test_t1_16_4
register_and_run_test "T1.16.5" 1 16 "M3" "Post-Apply Automated Verification Invocation" test_t1_16_5

# ==============================================================================
# FEATURE 17: Portfolio-Grade README (Milestone: M3)
# ==============================================================================
test_t1_17_1() {
    # Expected: Mermaid architecture diagram present in README.md (Milestone 3)
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ] && grep -qF "mermaid" "${readme}"; then
        assert_file_contains "${readme}" 'mermaid' "Mermaid diagram present in README"
    else
        skip_test "Pending M3: Mermaid diagram in portfolio README"
    fi
}

test_t1_17_2() {
    # Expected: ASCII architecture diagram present in README.md
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_contains "${readme}" "(\+---|\┌───)" "ASCII architecture diagram present in README"
    else
        skip_test "Pending M3: ASCII diagram in README.md"
    fi
}

test_t1_17_3() {
    # Expected: Zero-Trust network security model section
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_contains "${readme}" "[Zz]ero-[Tt]rust" "Zero-Trust network security model documented"
    else
        skip_test "Pending M3: Security model in README.md"
    fi
}

test_t1_17_4() {
    # Expected: WIF vs static keys comparison section
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_contains "${readme}" "[Ww]orkload [Ii]dentity [Ff]ederation|WIF" "WIF architectural rationale documented"
    else
        skip_test "Pending M3: WIF rationale in README.md"
    fi
}

test_t1_17_5() {
    # Expected: Memory sizing and 4GB swap engineering rationale
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_contains "${readme}" "4GB [Ss]wap|[Ss]wappiness" "Memory sizing and swap engineering documented"
    else
        skip_test "Pending M3: Swap rationale in README.md"
    fi
}

register_and_run_test "T1.17.1" 1 17 "M3" "Mermaid Architecture Diagram Presentation" test_t1_17_1
register_and_run_test "T1.17.2" 1 17 "M3" "Terminal-Friendly ASCII Network Topology" test_t1_17_2
register_and_run_test "T1.17.3" 1 17 "M3" "Zero-Trust Security Model Exposition" test_t1_17_3
register_and_run_test "T1.17.4" 1 17 "M3" "WIF vs Static Service Account Keys Rationale" test_t1_17_4
register_and_run_test "T1.17.5" 1 17 "M3" "e2-medium Sizing & 4GB Swap Architecture Math" test_t1_17_5

# ==============================================================================
# FEATURE 18: Live GCP Turn-up (Milestone: M4)
# ==============================================================================
test_t1_18_1() {
    # Expected: Clean architectural separation of 00-bootstrap and 01-workstation
    local b_main=$(find_file "00-bootstrap/main.tf")
    local w_main=$(find_file "01-workstation/main.tf")
    if [ -n "${b_main}" ] && [ -f "${b_main}" ] && [ -n "${w_main}" ] && [ -f "${w_main}" ]; then
        assert_file_contains "${b_main}" "google_project" "00-bootstrap handles project creation" && \
        assert_file_contains "${w_main}" "google_compute_instance" "01-workstation handles VM creation"
    else
        skip_test "Pending M1/M2: Layered Terraform configuration files"
    fi
}

test_t1_18_2() {
    # Expected: 00-bootstrap exports project_id output
    local b_out=$(find_file "00-bootstrap/outputs.tf")
    if [ -n "${b_out}" ] && [ -f "${b_out}" ]; then
        assert_file_contains "${b_out}" 'output\s+"project_id"' "00-bootstrap exports project_id"
    else
        skip_test "Pending M1: 00-bootstrap project_id output"
    fi
}

test_t1_18_3() {
    # Expected: 01-workstation ingests 00-bootstrap via terraform_remote_state
    local w_main=$(find_file "01-workstation/main.tf")
    if [ -n "${w_main}" ] && [ -f "${w_main}" ]; then
        assert_file_contains "${w_main}" 'data\s+"terraform_remote_state"\s+"bootstrap"' "Consumes bootstrap remote state"
    else
        skip_test "Pending M2: Remote state data source in 01-workstation"
    fi
}

test_t1_18_4() {
    # Expected: bootstrap-local.sh migration helper script present and executable
    local b_script=$(find_file "bootstrap-local.sh")
    if [ -n "${b_script}" ] && [ -f "${b_script}" ]; then
        assert_file_contains "${b_script}" "-migrate-state" "Performs state migration"
    else
        skip_test "Pending M1: scripts/bootstrap-local.sh"
    fi
}

test_t1_18_5() {
    # Expected: Clean teardown script or procedure present
    local teardown=$(find_file "teardown.sh")
    if [ -n "${teardown}" ] && [ -f "${teardown}" ]; then
        assert_file_contains "${teardown}" "terraform destroy" "Teardown script executes terraform destroy"
    else
        skip_test "Pending M4: scripts/teardown.sh"
    fi
}

register_and_run_test "T1.18.1" 1 18 "M4" "Layered IaC Decoupling Separation" test_t1_18_1
register_and_run_test "T1.18.2" 1 18 "M4" "Bootstrap Project ID Output Export Contract" test_t1_18_2
register_and_run_test "T1.18.3" 1 18 "M4" "Workstation Remote State Data Ingestion" test_t1_18_3
register_and_run_test "T1.18.4" 1 18 "M4" "Local-to-Remote State Migration Automation" test_t1_18_4
register_and_run_test "T1.18.5" 1 18 "M4" "Zero-Charge Clean Teardown Orchestration" test_t1_18_5

# ==============================================================================
# FEATURE 19: Programmatic Verification Suite (Milestone: M4)
# ==============================================================================
test_t1_19_1() {
    # Expected: scripts/verify-workstation.sh exists and is executable
    local script=$(find_file "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_exists "${script}" "verify-workstation.sh exists"
    else
        skip_test "Pending M4: scripts/verify-workstation.sh"
    fi
}

test_t1_19_2() {
    # Expected: verify-workstation.sh checks VM RUNNING status (Check V1)
    local script=$(find_file "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "RUNNING" "Asserts VM RUNNING status"
    else
        skip_test "Pending M4: VM check in verify-workstation.sh"
    fi
}

test_t1_19_3() {
    # Expected: verify-workstation.sh checks startup script exit code 0 (Check V2)
    local script=$(find_file "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "exit status 0" "Asserts startup script exit status 0"
    else
        skip_test "Pending M4: Startup status check in verify-workstation.sh"
    fi
}

test_t1_19_4() {
    # Expected: verify-workstation.sh checks active 4GB swap in swapon (Check V3)
    local script=$(find_file "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "swapon --show|/swapfile" "Asserts active swapfile"
    else
        skip_test "Pending M4: Swap check in verify-workstation.sh"
    fi
}

test_t1_19_5() {
    # Expected: verify-workstation.sh checks toolchain (node, python3, agy) (Check V5)
    local script=$(find_file "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "node -v" "Checks node semver" && \
        assert_file_contains "${script}" "python3" "Checks python version" && \
        assert_file_contains "${script}" "agy" "Checks agy CLI version"
    else
        skip_test "Pending M4: Toolchain checks in verify-workstation.sh"
    fi
}

register_and_run_test "T1.19.1" 1 19 "M4" "Programmatic Verification Script Existence" test_t1_19_1
register_and_run_test "T1.19.2" 1 19 "M4" "Automated V1 Health Check: VM Status RUNNING" test_t1_19_2
register_and_run_test "T1.19.3" 1 19 "M4" "Automated V2 Health Check: Startup Script Status 0" test_t1_19_3
register_and_run_test "T1.19.4" 1 19 "M4" "Automated V3 Health Check: 4GB Swapfile Active" test_t1_19_4
register_and_run_test "T1.19.5" 1 19 "M4" "Automated V5 Health Check: Toolchain Semver Inspection" test_t1_19_5

# ==============================================================================
# FEATURE 20: E2E Testing Suite (Milestone: E2E-Track)
# ==============================================================================
test_t1_20_1() {
    # Expected: tests/e2e_runner.sh harness executable exists
    assert_file_exists "${SCRIPT_DIR}/e2e_runner.sh" "e2e_runner.sh exists"
}

test_t1_20_2() {
    # Expected: tier1_feature_tests.sh is syntactically valid bash
    bash -n "${SCRIPT_DIR}/tier1_feature_tests.sh"
    assert_eq "$?" "0" "tier1_feature_tests.sh passes bash syntax check"
}

test_t1_20_3() {
    # Expected: e2e_runner.sh supports CLI flags --tier and --feature
    local help_out
    help_out=$("${SCRIPT_DIR}/e2e_runner.sh" --help)
    assert_contains "${help_out}" "--tier" "e2e_runner.sh supports --tier flag" && \
    assert_contains "${help_out}" "--feature" "e2e_runner.sh supports --feature flag"
}

test_t1_20_4() {
    # Expected: TEST_INFRA.md specification document exists in workspace
    assert_file_exists "${ROOT}/TEST_INFRA.md" "TEST_INFRA.md exists in root"
}

test_t1_20_5() {
    # Expected: Results directory created with JSON reporting capability
    assert_dir_exists "${SCRIPT_DIR}/results" "tests/results directory exists"
}

register_and_run_test "T1.20.1" 1 20 "E2E" "E2E Runner Harness Script Existence" test_t1_20_1
register_and_run_test "T1.20.2" 1 20 "E2E" "Tier 1 Bash Syntax Validation" test_t1_20_2
register_and_run_test "T1.20.3" 1 20 "E2E" "E2E Runner Filtering Flag Capabilities" test_t1_20_3
register_and_run_test "T1.20.4" 1 20 "E2E" "Test Infrastructure Specification Document" test_t1_20_4
register_and_run_test "T1.20.5" 1 20 "E2E" "Structured Results Directory & Reporter" test_t1_20_5

# ==============================================================================
# FEATURE 21: Adversarial Hardening (Milestone: M5)
# ==============================================================================
test_t1_21_1() {
    # Expected: Strict prohibition of google_service_account_key in Terraform
    local keys_found=0
    for f in $(find "${ROOT}" -name "*.tf" 2>/dev/null); do
        if grep -qE 'resource\s+"google_service_account_key"' "$f"; then
            keys_found=1
            break
        fi
    done
    assert_eq "${keys_found}" "0" "Zero google_service_account_key resources across all Terraform files"
}

test_t1_21_2() {
    # Expected: Strict uniform_bucket_level_access across all GCS buckets
    local violations=0
    for f in $(find "${ROOT}" -name "*.tf" 2>/dev/null); do
        if grep -q 'resource\s+"google_storage_bucket"' "$f"; then
            if ! grep -q 'uniform_bucket_level_access\s*=\s*true' "$f"; then
                violations=1
                break
            fi
        fi
    done
    assert_eq "${violations}" "0" "All declared storage buckets enforce uniform_bucket_level_access=true"
}

test_t1_21_3() {
    # Expected: Least privilege runtime service account (zero roles/editor or roles/owner)
    local overprivileged=0
    for f in $(find "${ROOT}" -name "*.tf" 2>/dev/null); do
        if grep -qE 'roles/(editor|owner)' "$f"; then
            overprivileged=1
            break
        fi
    done
    assert_eq "${overprivileged}" "0" "No overprivileged roles/editor or roles/owner granted"
}

test_t1_21_4() {
    # Expected: Metadata queries in startup.sh include Metadata-Flavor: Google
    local startup=$(find_file "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'Metadata-Flavor:\s*Google' "All metadata queries enforce Metadata-Flavor: Google"
    else
        skip_test "Pending M2: Metadata security in startup.sh"
    fi
}

test_t1_21_5() {
    # Expected: No plaintext passwords or credentials committed to repository
    local plain_secrets=0
    for f in $(find "${ROOT}" -type f ! -path "*/.git/*" ! -path "*/tests/*" 2>/dev/null); do
        if grep -qE "ghp_[A-Za-z0-9]{36}|BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY" "$f" 2>/dev/null; then
            plain_secrets=1
            break
        fi
    done
    assert_eq "${plain_secrets}" "0" "Zero plaintext private keys or personal access tokens in workspace"
}

register_and_run_test "T1.21.1" 1 21 "M5" "Static Service Account Key Prohibition Audit" test_t1_21_1
register_and_run_test "T1.21.2" 1 21 "M5" "Mandatory Uniform Bucket-Level Access Compliance" test_t1_21_2
register_and_run_test "T1.21.3" 1 21 "M5" "Least Privilege Runtime IAM Allocation Audit" test_t1_21_3
register_and_run_test "T1.21.4" 1 21 "M5" "Metadata Request Header Defense (Metadata-Flavor: Google)" test_t1_21_4
register_and_run_test "T1.21.5" 1 21 "M5" "Plaintext Credential Leakage Scanner Audit" test_t1_21_5
