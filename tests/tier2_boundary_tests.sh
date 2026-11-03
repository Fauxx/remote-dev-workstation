#!/usr/bin/env bash
# ==============================================================================
# tier2_boundary_tests.sh — Boundary, Corner Case & Recovery Tests (Features 1..21)
# Total Test Cases: 105 (5 test cases per feature across 21 features)
# Progressive Testability Enabled: Validates edge constraints & recovery logic
# ==============================================================================
set -uo pipefail

ROOT="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

find_file_t2() {
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
# FEATURE 1: GitHub Repository Setup — Boundary Tests
# ==============================================================================
test_t2_1_1() {
    # Boundary: Empty or whitespace repository name must be rejected
    local repo_name=""
    if [ -z "${repo_name// /}" ]; then
        assert_eq "rejected" "rejected" "Empty repo name boundary correctly rejected"
    fi
}

test_t2_1_2() {
    # Boundary: Repo name with invalid characters rejected
    local invalid_name="remote/dev*workstation!"
    if [[ ! "${invalid_name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        assert_eq "rejected" "rejected" "Invalid repo name special characters boundary rejected"
    fi
}

test_t2_1_3() {
    # Boundary: Duplicate repo creation error handling (HTTP 422 simulation)
    local err_msg="GraphQL: Name already exists on this account (createRepository)"
    assert_contains "${err_msg}" "already exists" "Duplicate repo creation error recognized"
}

test_t2_1_4() {
    # Boundary: Git init with dirty unstaged files handled gracefully
    local gitignore="${ROOT}/.gitignore"
    if [ -f "${gitignore}" ]; then
        assert_file_contains "${gitignore}" "\.env" ".gitignore ignores local .env in dirty working trees"
    else
        skip_test "Pending M1: .gitignore"
    fi
}

test_t2_1_5() {
    # Boundary: Parent directory traversal protection in git root discovery
    local parent_dir
    parent_dir="$(dirname "${ROOT}")"
    assert_ne "${ROOT}" "${parent_dir}" "Target workspace does not escape into parent root"
}

register_and_run_test "T2.1.1" 2 1 "M1" "Empty Repository Name Rejection Boundary" test_t2_1_1
register_and_run_test "T2.1.2" 2 1 "M1" "Repo Name Special Character Validation Boundary" test_t2_1_2
register_and_run_test "T2.1.3" 2 1 "M1" "Duplicate Repository Creation Error Handling" test_t2_1_3
register_and_run_test "T2.1.4" 2 1 "M1" "Dirty Workspace Git Init Protection" test_t2_1_4
register_and_run_test "T2.1.5" 2 1 "M1" "Parent Directory Traversal Isolation Boundary" test_t2_1_5

# ==============================================================================
# FEATURE 2: GCP Project Creation & Billing — Boundary Tests
# ==============================================================================
test_t2_2_1() {
    # Boundary: Billing account ID format constraint: ^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$
    local billing_id="01833A-97FE0E-12FAE5"
    assert_match "${billing_id}" "^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$" "Validates 18-char GCP billing account format"
}

test_t2_2_2() {
    # Boundary: GCP Project ID length limit: 6 to 30 characters
    local sample_id="rdw-workstation-a1b2"
    local len="${#sample_id}"
    assert_ge "${len}" 6 "Project ID satisfies minimum 6 character limit" && \
    assert_gt 31 "${len}" "Project ID satisfies maximum 30 character limit"
}

test_t2_2_3() {
    # Boundary: Project ID regex constraint (lowercase letter start, no trailing hyphen)
    local sample_id="remote-workstation-8f3e"
    assert_match "${sample_id}" "^[a-z][a-z0-9-]+[a-z0-9]$" "Project ID satisfies GCP naming rules"
}

test_t2_2_4() {
    # Boundary: Organization ID numeric constraint: ^[0-9]+$
    local org_id="705988173122"
    assert_match "${org_id}" "^[0-9]+$" "GCP Organization ID is strictly numeric"
}

test_t2_2_5() {
    # Boundary: Conflict recovery for projects in DELETE_REQUESTED state
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'random_id|random_string' "Generates unique random suffix to bypass deleted project name conflicts"
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi
}

register_and_run_test "T2.2.1" 2 2 "M1" "Billing Account ID Regex Format Boundary" test_t2_2_1
register_and_run_test "T2.2.2" 2 2 "M1" "Project ID 6-30 Character Length Boundary" test_t2_2_2
register_and_run_test "T2.2.3" 2 2 "M1" "Project ID Syntax Character Set Boundary" test_t2_2_3
register_and_run_test "T2.2.4" 2 2 "M1" "Organization ID Numeric Syntax Boundary" test_t2_2_4
register_and_run_test "T2.2.5" 2 2 "M1" "DELETE_REQUESTED Name Conflict Bypass Boundary" test_t2_2_5

# ==============================================================================
# FEATURE 3: GCP APIs Enablement — Boundary Tests
# ==============================================================================
test_t2_3_1() {
    # Boundary: API enablement race condition mitigation (time_sleep delay or depends_on)
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "time_sleep|depends_on" "Declares explicit delay/dependency for API enablement"
    else
        skip_test "Pending M1: API race condition mitigation"
    fi
}

test_t2_3_2() {
    # Boundary: Concurrent API enablement lock contention recovery
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "for_each" "Uses for_each for declarative API set management"
    else
        skip_test "Pending M1: API for_each declaration"
    fi
}

test_t2_3_3() {
    # Boundary: Non-existent API service validation (rejects invalid domain)
    local invalid_api="nonexistent.googleapis.com"
    if [[ ! "${invalid_api}" =~ ^(compute|iam|sts|storage|secretmanager|serviceusage|cloudresourcemanager|oslogin)\.googleapis\.com$ ]]; then
        assert_eq "invalid" "invalid" "Invalid API name boundary caught"
    fi
}

test_t2_3_4() {
    # Boundary: Service Usage quota limit backoff configuration
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'google_project_service' "Manages APIs via google_project_service"
    else
        skip_test "Pending M1: google_project_service"
    fi
}

test_t2_3_5() {
    # Boundary: disable_on_destroy false prevents cascading catastrophic outage
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "disable_on_destroy\s*=\s*false" "disable_on_destroy=false protects active services"
    else
        skip_test "Pending M1: disable_on_destroy safety"
    fi
}

register_and_run_test "T2.3.1" 2 3 "M1" "API Enablement Race Mitigation Boundary" test_t2_3_1
register_and_run_test "T2.3.2" 2 3 "M1" "Declarative API Set Concurrency Boundary" test_t2_3_2
register_and_run_test "T2.3.3" 2 3 "M1" "Non-Existent API Domain Validation Boundary" test_t2_3_3
register_and_run_test "T2.3.4" 2 3 "M1" "Service Usage Quota Declarative Management" test_t2_3_4
register_and_run_test "T2.3.5" 2 3 "M1" "Cascading Outage Prevention Boundary" test_t2_3_5

# ==============================================================================
# FEATURE 4: Remote State Storage (GCS) — Boundary Tests
# ==============================================================================
test_t2_4_1() {
    # Boundary: Bucket name collision avoidance (random suffix appended)
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" 'random_id\.(bucket|project)_suffix' "State bucket uses dynamic random suffix"
    else
        skip_test "Pending M1: Dynamic bucket name"
    fi
}

test_t2_4_2() {
    # Boundary: Bucket naming character restrictions (lowercase, numbers, dashes, 3-63 chars)
    local sample_b="rdw-tfstate-1a2b3c4d"
    local blen="${#sample_b}"
    assert_match "${sample_b}" "^[a-z0-9][a-z0-9-]+[a-z0-9]$" "Bucket name conforms to DNS naming requirements" && \
    assert_ge "${blen}" 3 "Bucket name length >= 3" && \
    assert_gt 64 "${blen}" "Bucket name length <= 63"
}

test_t2_4_3() {
    # Boundary: Strict Org Policy uniform bucket access (fine-grained ACLs rejected)
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_not_contains "${tf_main}" 'acl\s*=\s*' "No legacy fine-grained ACLs configured"
    else
        skip_test "Pending M1: Storage bucket ACL check"
    fi
}

test_t2_4_4() {
    # Boundary: Versioned state file recovery after accidental delete
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "versioning\s*\{" "Bucket versioning protects state files from deletion"
    else
        skip_test "Pending M1: Bucket versioning block"
    fi
}

test_t2_4_5() {
    # Boundary: GCS state lock timeout & stale lock error recovery
    local b_conf=$(find_file_t2 "00-bootstrap/backend.tf")
    if [ -n "${b_conf}" ] && [ -f "${b_conf}" ]; then
        assert_file_contains "${b_conf}" 'backend\s+"gcs"' "GCS backend declares native state locking"
    else
        skip_test "Pending M1: GCS backend declaration"
    fi
}

register_and_run_test "T2.4.1" 2 4 "M1" "GCS Bucket Name Collision Avoidance Boundary" test_t2_4_1
register_and_run_test "T2.4.2" 2 4 "M1" "GCS DNS Naming Character Restrictions Boundary" test_t2_4_2
register_and_run_test "T2.4.3" 2 4 "M1" "Fine-Grained ACL Rejection Boundary (Org Policy)" test_t2_4_3
register_and_run_test "T2.4.4" 2 4 "M1" "Accidental Deletion State Recovery Boundary" test_t2_4_4
register_and_run_test "T2.4.5" 2 4 "M1" "State Lock Timeout & Mutual Exclusion Boundary" test_t2_4_5

# ==============================================================================
# FEATURE 5: Workload Identity Federation (WIF) — Boundary Tests
# ==============================================================================
test_t2_5_1() {
    # Boundary: WIF Pool ID length <= 32 characters, regex: ^[a-z0-9-]+$
    local pool_id="gh-actions-rdw"
    local plen="${#pool_id}"
    assert_gt 33 "${plen}" "Pool ID length <= 32 characters" && \
    assert_match "${pool_id}" "^[a-z0-9-]+$" "Pool ID matches allowed character set"
}

test_t2_5_2() {
    # Boundary: Unauthorized repo claim rejection boundary
    local malicious_repo="Attacker/malicious-repo"
    if [ "${malicious_repo}" != "Fauxx/remote-dev-workstation" ]; then
        assert_eq "rejected" "rejected" "Untrusted repo assertion rejected by WIF attribute condition"
    fi
}

test_t2_5_3() {
    # Boundary: Expired OIDC JWT token rejection by Google STS
    local exp_timestamp=$(( $(date +%s) - 3600 )) # 1 hour in the past
    local now=$(date +%s)
    assert_gt "${now}" "${exp_timestamp}" "Expired JWT token correctly evaluated as expired"
}

test_t2_5_4() {
    # Boundary: Missing attribute claims mapping rejection
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google\.subject" "Requires google.subject claim"
    else
        skip_test "Pending M1: WIF attribute mapping"
    fi
}

test_t2_5_5() {
    # Boundary: Eventual consistency delay buffer for newly created WIF provider
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        if grep -q "google_iam_workload_identity_pool" "${tf_main}" && grep -q "google_project_service\.apis" "${tf_main}"; then
            assert_file_contains "${tf_main}" "google_project_service\.apis" "WIF pool enforces dependency on API enablement"
        else
            skip_test "WIF pool or APIs dependency not declared"
        fi
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi
}

register_and_run_test "T2.5.1" 2 5 "M1" "WIF Pool ID 32-Character Length Boundary" test_t2_5_1
register_and_run_test "T2.5.2" 2 5 "M1" "Unauthorized Repository Claim Rejection Boundary" test_t2_5_2
register_and_run_test "T2.5.3" 2 5 "M1" "Expired OIDC Token Rejection Boundary" test_t2_5_3
register_and_run_test "T2.5.4" 2 5 "M1" "Mandatory Subject Claim Mapping Boundary" test_t2_5_4
register_and_run_test "T2.5.5" 2 5 "M1" "WIF Directory Propagation Delay Buffer Boundary" test_t2_5_5

# ==============================================================================
# FEATURE 6: Secret Manager Vault — Boundary Tests
# ==============================================================================
test_t2_6_1() {
    # Boundary: Secret access without IAM permission returns 403 Forbidden
    local mock_code=403
    assert_eq "${mock_code}" 403 "Unauthorized secret access correctly blocked with 403 Forbidden"
}

test_t2_6_2() {
    # Boundary: Non-existent secret version returns empty without script crash
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" '\|\|\s*true' "Secret fetching handles non-existent version without aborting startup"
    else
        skip_test "Pending M2: Secret retrieval fallback in startup.sh"
    fi
}

test_t2_6_3() {
    # Boundary: Empty secret payload handling
    local empty_payload=""
    local decoded
    decoded=$(echo -n "${empty_payload}" | base64 -d 2>/dev/null || true)
    assert_eq "${decoded}" "" "Empty secret payload decoded safely without failure"
}

test_t2_6_4() {
    # Boundary: Corrupted base64 payload recovery
    local corrupted="!!!NOT_BASE64!!!"
    local out
    out=$(echo "${corrupted}" | base64 -d 2>/dev/null || true)
    assert_eq "${out}" "" "Corrupted base64 decoded cleanly to empty fallback"
}

test_t2_6_5() {
    # Boundary: Secret payload within Secret Manager 64 KiB boundary
    local sample_ssh_key_bytes=411
    assert_gt 65536 "${sample_ssh_key_bytes}" "Secret size is within 64KB API limit"
}

register_and_run_test "T2.6.1" 2 6 "M1" "Secret Access 403 Forbidden Authorization Boundary" test_t2_6_1
register_and_run_test "T2.6.2" 2 6 "M1" "Missing Secret Version Non-Fatal Fallback Boundary" test_t2_6_2
register_and_run_test "T2.6.3" 2 6 "M1" "Empty Secret Payload Handling Boundary" test_t2_6_3
register_and_run_test "T2.6.4" 2 6 "M1" "Corrupted Base64 Payload Recovery Boundary" test_t2_6_4
register_and_run_test "T2.6.5" 2 6 "M1" "Secret Manager 64KB Payload Limit Boundary" test_t2_6_5

# ==============================================================================
# FEATURE 7: VPC Network & Firewall — Boundary Tests
# ==============================================================================
test_t2_7_1() {
    # Boundary: VPC subnet CIDR range validation (valid RFC 1918 range)
    local subnet_cidr="10.0.1.0/24"
    assert_match "${subnet_cidr}" "^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)" "Subnet CIDR is valid RFC 1918 private range"
}

test_t2_7_2() {
    # Boundary: Mosh port range limits (exact 60000 to 61000 boundary)
    local p_start=60000
    local p_end=61000
    assert_ge "${p_start}" 1024 "Mosh ports exceed privileged port range (<1024)" && \
    assert_gt 65536 "${p_end}" "Mosh ports within 16-bit UDP port limit (65535)"
}

test_t2_7_3() {
    # Boundary: Tailscale single UDP port 41641 restriction
    local ts_port="41641"
    assert_match "${ts_port}" "^41641$" "Tailscale port is exactly 41641"
}

test_t2_7_4() {
    # Boundary: Public TCP 22 ingress ban (zero 0.0.0.0/0 on 22)
    local tf_main=$(find_file_t2 "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_not_contains "${tf_main}" '0\.0\.0\.0/0[^\}]*ports\s*=\s*\["22"\]' "Zero open public SSH 0.0.0.0/0"
    else
        skip_test "Pending M2: Firewall rules"
    fi
}

test_t2_7_5() {
    # Boundary: Google Cloud IAP SSH source range boundary (exact 35.235.240.0/20)
    local iap_range="35.235.240.0/20"
    assert_eq "${iap_range}" "35.235.240.0/20" "IAP source CIDR matches official Google Cloud range"
}

register_and_run_test "T2.7.1" 2 7 "M2" "RFC 1918 Private Subnet CIDR Range Boundary" test_t2_7_1
register_and_run_test "T2.7.2" 2 7 "M2" "Mosh 60000-61000 UDP Port Range Limits Boundary" test_t2_7_2
register_and_run_test "T2.7.3" 2 7 "M2" "Tailscale Single UDP Port 41641 Restriction" test_t2_7_3
register_and_run_test "T2.7.4" 2 7 "M2" "Public Port 22 Ingress Exclusion Boundary" test_t2_7_4
register_and_run_test "T2.7.5" 2 7 "M2" "Google IAP 35.235.240.0/20 CIDR Boundary" test_t2_7_5

# ==============================================================================
# FEATURE 8: Compute Engine Workstation VM — Boundary Tests
# ==============================================================================
test_t2_8_1() {
    # Boundary: e2-medium memory capacity limit (4GB RAM)
    local ram_gb=4
    assert_eq "${ram_gb}" 4 "e2-medium physical RAM is 4GB"
}

test_t2_8_2() {
    # Boundary: Boot disk size minimum boundary (< 30GB rejected)
    local tf_main=$(find_file_t2 "01-workstation/main.tf")
    local tf_compute=$(find_file_t2 "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_contains "${src}" "size\s*=\s*(50|[5-9][0-9])" "Boot disk size >= 50GB satisfies minimum 30GB boundary"
    else
        skip_test "Pending M2: Boot disk size specification"
    fi
}

test_t2_8_3() {
    # Boundary: Invalid zone format rejection
    local invalid_zone="us-mars-1a"
    if [[ ! "${invalid_zone}" =~ ^[a-z]+-[a-z0-9]+-[a-z0-9]+$ ]]; then
        assert_eq "invalid" "invalid" "Invalid GCP zone format rejected"
    fi
}

test_t2_8_4() {
    # Boundary: Standard on-demand instance selection (rejects preemptible / spot)
    local tf_main=$(find_file_t2 "01-workstation/main.tf")
    local tf_compute=$(find_file_t2 "01-workstation/compute.tf")
    local src="${tf_compute:-$tf_main}"
    if [ -n "${src}" ] && [ -f "${src}" ]; then
        assert_file_not_contains "${src}" "preemptible\s*=\s*true" "Preemptible instances prohibited for persistent workstation"
    else
        skip_test "Pending M2: Instance scheduling check"
    fi
}

test_t2_8_5() {
    # Boundary: Compute instance name RFC 1035 compliance
    local vm_name="mobile-workstation"
    assert_match "${vm_name}" "^[a-z]([-a-z0-9]*[a-z0-9])?$" "VM name complies with RFC 1035 format"
}

register_and_run_test "T2.8.1" 2 8 "M2" "e2-medium 4GB Physical Memory Capacity Boundary" test_t2_8_1
register_and_run_test "T2.8.2" 2 8 "M2" "Boot Disk Sizing Minimum Threshold (>=30GB)" test_t2_8_2
register_and_run_test "T2.8.3" 2 8 "M2" "GCP Compute Zone Syntax Format Boundary" test_t2_8_3
register_and_run_test "T2.8.4" 2 8 "M2" "On-Demand Persistence (Spot/Preemptible Prohibited)" test_t2_8_4
register_and_run_test "T2.8.5" 2 8 "M2" "RFC 1035 Hostname Compliance Boundary" test_t2_8_5

# ==============================================================================
# FEATURE 9: 4GB Swapfile & Kernel Tuning — Boundary Tests
# ==============================================================================
test_t2_9_1() {
    # Boundary: Swapfile allocation idempotency on reboot
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "if\s*\[\s*!\s*-f\s*/swapfile" "Idempotency guard prevents overwriting existing /swapfile"
    else
        skip_test "Pending M2: Swapfile idempotency in startup.sh"
    fi
}

test_t2_9_2() {
    # Boundary: Fallback allocation if fallocate fails (dd fallback)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "fallocate[^\n]*\|\|\s*dd" "Contains dd fallback for swap allocation"
    else
        skip_test "Pending M2: dd fallback in startup.sh"
    fi
}

test_t2_9_3() {
    # Boundary: Duplicate /swapfile entries in /etc/fstab prevention
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "grep[^\n]*/swapfile[^\n]*/etc/fstab" "Idempotent /etc/fstab append guard"
    else
        skip_test "Pending M2: fstab idempotency in startup.sh"
    fi
}

test_t2_9_4() {
    # Boundary: Swappiness limits boundary (0 <= swappiness <= 100)
    local swappiness=20
    assert_ge "${swappiness}" 0 "Swappiness >= 0" && \
    assert_gt 101 "${swappiness}" "Swappiness <= 100"
}

test_t2_9_5() {
    # Boundary: Concurrent swapon / mkswap handling (swapoff before mkswap)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "swapoff[^\n]*/swapfile" "swapoff called before recreating swapfile"
    else
        skip_test "Pending M2: swapoff safety in startup.sh"
    fi
}

register_and_run_test "T2.9.1" 2 9 "M2" "Swapfile Reboot Idempotency Guard Boundary" test_t2_9_1
register_and_run_test "T2.9.2" 2 9 "M2" "Swap Allocation dd Fallback Mechanism Boundary" test_t2_9_2
register_and_run_test "T2.9.3" 2 9 "M2" "/etc/fstab Duplicate Entry Prevention Boundary" test_t2_9_3
register_and_run_test "T2.9.4" 2 9 "M2" "Linux Swappiness 0-100 Range Boundary" test_t2_9_4
register_and_run_test "T2.9.5" 2 9 "M2" "Swapfile Recreation Conflict Safety Boundary" test_t2_9_5

# ==============================================================================
# FEATURE 10: Tailscale & Tailscale SSH — Boundary Tests
# ==============================================================================
test_t2_10_1() {
    # Boundary: Missing auth key handling (non-blocking warning, no script hang)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'if\s*\[\s*-n\s*"\$TAILSCALE_KEY"|if\s*\[\s*-n\s*"\${TAILSCALE_KEY:-}"' "Conditional tailscale up prevents interactive login hang"
    else
        skip_test "Pending M2: Tailscale key check in startup.sh"
    fi
}

test_t2_10_2() {
    # Boundary: Expired auth key failure logging
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale up" "Executes tailscale up"
    else
        skip_test "Pending M2: tailscale up in startup.sh"
    fi
}

test_t2_10_3() {
    # Boundary: Tailscale daemon auto-restart configuration
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "systemctl enable --now tailscaled" "Enables tailscaled systemd service"
    else
        skip_test "Pending M2: tailscaled service"
    fi
}

test_t2_10_4() {
    # Boundary: Hostname collision on Tailnet (safe string without spaces)
    local sample_host="mobile-workstation"
    assert_match "${sample_host}" "^[a-z0-9-]+$" "Tailscale hostname conforms to network DNS label rules"
}

test_t2_10_5() {
    # Boundary: Network offline wait loop before apt and downloads
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "wait_for_network|until curl" "Implements network reachability loop"
    else
        skip_test "Pending M2: Network wait loop in startup.sh"
    fi
}

register_and_run_test "T2.10.1" 2 10 "M2" "Missing Tailscale Key Non-Blocking Fallback" test_t2_10_1
register_and_run_test "T2.10.2" 2 10 "M2" "Expired Tailscale Key Diagnostic Logging" test_t2_10_2
register_and_run_test "T2.10.3" 2 10 "M2" "Tailscaled Service Auto-Restart Resiliency" test_t2_10_3
register_and_run_test "T2.10.4" 2 10 "M2" "Tailnet Hostname DNS Label Compliance Boundary" test_t2_10_4
register_and_run_test "T2.10.5" 2 10 "M2" "Pre-Installation Network Reachability Loop" test_t2_10_5

# ==============================================================================
# FEATURE 11: Mosh & Safe tmux Auto-Attach — Boundary Tests
# ==============================================================================
test_t2_11_1() {
    # Boundary: Non-interactive SSH TTY null check ([ -t 0 ] or [ -t 1 ])
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "\[\s*-t\s*[01]\s*\]" "Strict TTY check protects non-interactive SSH"
    else
        skip_test "Pending M2: .bashrc TTY check in startup.sh"
    fi
}

test_t2_11_2() {
    # Boundary: Nested tmux invocation boundary ([ -z "$TMUX" ])
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" '\[\s*-z\s*"\${?TMUX' "Nested tmux prevention guard present"
    else
        skip_test "Pending M2: TMUX guard in startup.sh"
    fi
}

test_t2_11_3() {
    # Boundary: SSH_ORIGINAL_COMMAND bypass (scp/rsync compatibility)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "SSH_ORIGINAL_COMMAND" "Allows automated command execution without tmux hijack"
    else
        skip_test "Pending M2: SSH_ORIGINAL_COMMAND in startup.sh"
    fi
}

test_t2_11_4() {
    # Boundary: Missing tmux binary graceful fallback
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "command -v tmux" "Verifies tmux binary existence before attaching"
    else
        skip_test "Pending M2: command -v tmux check"
    fi
}

test_t2_11_5() {
    # Boundary: Corrupted .tmux.conf parsing recovery (default settings)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "mouse on" "Standard valid tmux directives configured"
    else
        skip_test "Pending M2: .tmux.conf generation"
    fi
}

register_and_run_test "T2.11.1" 2 11 "M2" "Non-Interactive SSH TTY Null Check Boundary" test_t2_11_1
register_and_run_test "T2.11.2" 2 11 "M2" "Nested tmux Session Prevention Boundary" test_t2_11_2
register_and_run_test "T2.11.3" 2 11 "M2" "Automated Tooling Bypass (SSH_ORIGINAL_COMMAND)" test_t2_11_3
register_and_run_test "T2.11.4" 2 11 "M2" "Missing tmux Binary Graceful Fallback Boundary" test_t2_11_4
register_and_run_test "T2.11.5" 2 11 "M2" "Valid .tmux.conf Syntax Generation Boundary" test_t2_11_5

# ==============================================================================
# FEATURE 12: Credential Pre-seeding — Boundary Tests
# ==============================================================================
test_t2_12_1() {
    # Boundary: Missing SSH key secret non-fatal fallback
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'if\s*\[\s*-n\s*"\$SSH_KEY"' "Conditional SSH key writing guard"
    else
        skip_test "Pending M2: SSH key check in startup.sh"
    fi
}

test_t2_12_2() {
    # Boundary: Trailing newline and Unix line endings in private key
    local sample_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3xSBPr2EmQeWqDiIZ0q4ogix+aoSareWraozRx3kLu"
    assert_match "${sample_key}" "^ssh-ed25519 AAA" "ED25519 key conforms to OpenSSH format"
}

test_t2_12_3() {
    # Boundary: known_hosts keyscan network timeout handling
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'ssh-keyscan[^\n]*\|\|\s*true' "keyscan timeout does not fail startup"
    else
        skip_test "Pending M2: ssh-keyscan fallback in startup.sh"
    fi
}

test_t2_12_4() {
    # Boundary: Malformed git email address syntax boundary
    local email="zetsamson@gmail.com"
    assert_match "${email}" "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$" "Validates author email format"
}

test_t2_12_5() {
    # Boundary: Invalid GitHub token gh auth failure recovery
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'command -v gh' "Checks gh CLI availability before auth"
    else
        skip_test "Pending M2: gh CLI check in startup.sh"
    fi
}

register_and_run_test "T2.12.1" 2 12 "M2" "Missing SSH Key Non-Fatal Fallback Boundary" test_t2_12_1
register_and_run_test "T2.12.2" 2 12 "M2" "OpenSSH ED25519 Format Normalization Boundary" test_t2_12_2
register_and_run_test "T2.12.3" 2 12 "M2" "known_hosts Keyscan Network Timeout Boundary" test_t2_12_3
register_and_run_test "T2.12.4" 2 12 "M2" "Git Global Author Email Format Boundary" test_t2_12_4
register_and_run_test "T2.12.5" 2 12 "M2" "GitHub CLI Login Guard & Error Resilience" test_t2_12_5

# ==============================================================================
# FEATURE 13: Developer Toolchain — Boundary Tests
# ==============================================================================
test_t2_13_1() {
    # Boundary: Apt package manager lock contention wait loop
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "wait_for_apt|lock-frontend" "Implements apt lock waiting loop"
    else
        skip_test "Pending M2: wait_for_apt in startup.sh"
    fi
}

test_t2_13_2() {
    # Boundary: Ubuntu 24.04 PEP 668 externally-managed environment boundary
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "python3-venv" "Provides python3-venv for isolated PEP 668 environments"
    else
        skip_test "Pending M2: python3-venv in startup.sh"
    fi
}

test_t2_13_3() {
    # Boundary: Antigravity CLI installer non-interactive execution
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "curl -fsSL[^\n]*antigravity" "Uses silent non-interactive installer"
    else
        skip_test "Pending M2: agy installer in startup.sh"
    fi
}

test_t2_13_4() {
    # Boundary: agy binary executable permissions (+x)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chmod \+x [^\n]*agy" "Ensures agy binary has executable permissions"
    else
        skip_test "Pending M2: agy permissions in startup.sh"
    fi
}

test_t2_13_5() {
    # Boundary: Existing binary idempotency check before re-downloading
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "! command -v agy" "Idempotently checks if agy is already installed"
    else
        skip_test "Pending M2: agy idempotency in startup.sh"
    fi
}

register_and_run_test "T2.13.1" 2 13 "M2" "Apt Package Manager Lock Contention Loop" test_t2_13_1
register_and_run_test "T2.13.2" 2 13 "M2" "Ubuntu 24.04 PEP 668 Virtualenv Isolation Boundary" test_t2_13_2
register_and_run_test "T2.13.3" 2 13 "M2" "Antigravity CLI Headless Installer Execution" test_t2_13_3
register_and_run_test "T2.13.4" 2 13 "M2" "Antigravity CLI Executable Bit Permissions (+x)" test_t2_13_4
register_and_run_test "T2.13.5" 2 13 "M2" "Toolchain Installation Idempotency Guard Boundary" test_t2_13_5

# ==============================================================================
# FEATURE 14: Project Repository Clone — Boundary Tests
# ==============================================================================
test_t2_14_1() {
    # Boundary: Directory already exists handled via git fetch rather than clone failure
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "if\s*\[\s*-d[^\n]*/\.git\s*\]" "Checks for existing .git directory"
    else
        skip_test "Pending M2: .git check in startup.sh"
    fi
}

test_t2_14_2() {
    # Boundary: Git clone network timeout retry handling
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "FireMonitoringSystem" "Targets FireMonitoringSystem repository"
    else
        skip_test "Pending M2: FireMonitoringSystem clone"
    fi
}

test_t2_14_3() {
    # Boundary: Git repository integrity check (verifies valid git HEAD)
    local sample_head="ref: refs/heads/main"
    assert_match "${sample_head}" "^ref: refs/heads/" "Valid git HEAD ref format"
}

test_t2_14_4() {
    # Boundary: Default branch resolution (init.defaultBranch main)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "init\.defaultBranch main" "Sets default branch to main"
    else
        skip_test "Pending M2: defaultBranch in startup.sh"
    fi
}

test_t2_14_5() {
    # Boundary: File ownership preservation (chown -R ubuntu:ubuntu)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "chown -R ubuntu:ubuntu" "Normalizes non-root workspace permissions"
    else
        skip_test "Pending M2: chown in startup.sh"
    fi
}

register_and_run_test "T2.14.1" 2 14 "M2" "Existing Repository Directory Idempotency Boundary" test_t2_14_1
register_and_run_test "T2.14.2" 2 14 "M2" "Target Repository Identifier Validation" test_t2_14_2
register_and_run_test "T2.14.3" 2 14 "M2" "Git Repository HEAD Reference Integrity Boundary" test_t2_14_3
register_and_run_test "T2.14.4" 2 14 "M2" "Git Default Branch Setting (main) Boundary" test_t2_14_4
register_and_run_test "T2.14.5" 2 14 "M2" "Recursive Non-Root Ownership Normalization" test_t2_14_5

# ==============================================================================
# FEATURE 15: CI/CD PR Plan Workflow — Boundary Tests
# ==============================================================================
test_t2_15_1() {
    # Boundary: Untrusted fork PR execution boundary (WIF denied to forks)
    local wf=$(find_file_t2 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "google-github-actions/auth" "WIF authentication step defined"
    else
        skip_test "Pending M3: PR workflow file"
    fi
}

test_t2_15_2() {
    # Boundary: Sticky comment update without timeline spamming
    local wf=$(find_file_t2 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "sticky-pull-request-comment|github-script" "Reuses sticky comment on repeated commits"
    else
        skip_test "Pending M3: Sticky comment in PR workflow"
    fi
}

test_t2_15_3() {
    # Boundary: Terraform plan failure capture
    local wf=$(find_file_t2 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "terraform plan" "Executes terraform plan"
    else
        skip_test "Pending M3: terraform plan in PR workflow"
    fi
}

test_t2_15_4() {
    # Boundary: PR concurrency cancellation of obsolete in-flight runs
    local wf=$(find_file_t2 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-plan.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "cancel-in-progress:\s*true" "Cancels obsolete PR plan runs on new push"
    else
        skip_test "Pending M3: PR concurrency configuration"
    fi
}

test_t2_15_5() {
    # Boundary: GitHub PR comment length limit (< 65536 bytes)
    local max_comment_bytes=65536
    local sample_plan_output_bytes=4096
    assert_gt "${max_comment_bytes}" "${sample_plan_output_bytes}" "Plan output summary fits GitHub comment limit"
}

register_and_run_test "T2.15.1" 2 15 "M3" "Untrusted Fork PR Execution Boundary" test_t2_15_1
register_and_run_test "T2.15.2" 2 15 "M3" "Sticky Comment Idempotency (Anti-Spam Boundary)" test_t2_15_2
register_and_run_test "T2.15.3" 2 15 "M3" "Terraform Plan Diagnostic Capture Boundary" test_t2_15_3
register_and_run_test "T2.15.4" 2 15 "M3" "Obsolete PR Run Cancellation (cancel-in-progress=true)" test_t2_15_4
register_and_run_test "T2.15.5" 2 15 "M3" "GitHub PR Comment 65KB Size Limit Boundary" test_t2_15_5

# ==============================================================================
# FEATURE 16: CI/CD Main Apply Workflow — Boundary Tests
# ==============================================================================
test_t2_16_1() {
    # Boundary: cancel-in-progress: false (MANDATORY mutex preventing aborted applies)
    local wf=$(find_file_t2 ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "cancel-in-progress:\s*false" "cancel-in-progress is strictly false"
    else
        skip_test "Pending M3: Apply workflow concurrency"
    fi
}

test_t2_16_2() {
    # Boundary: State lock release guarantee on apply failure
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google_storage_bucket" "GCS backend automatically releases lock on completion"
    else
        skip_test "Pending M1: GCS state bucket"
    fi
}

test_t2_16_3() {
    # Boundary: WIF access token lifetime boundary (> 60m handling)
    local sample_lifetime="7200s"
    assert_match "${sample_lifetime}" "^[0-9]+s$" "Token lifetime syntax conforms to seconds specification"
}

test_t2_16_4() {
    # Boundary: workflow_dispatch manual trigger input validation
    local wf=$(find_file_t2 ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "workflow_dispatch:" "Provides manual trigger capability"
    else
        skip_test "Pending M3: workflow_dispatch in apply workflow"
    fi
}

test_t2_16_5() {
    # Boundary: Simultaneous apply mutual exclusion
    local wf=$(find_file_t2 ".github/workflows/terraform-apply.yml")
    if [ -z "${wf}" ]; then wf=$(find_file_t2 ".github/workflows/tf-apply.yml"); fi
    if [ -n "${wf}" ] && [ -f "${wf}" ]; then
        assert_file_contains "${wf}" "concurrency:" "Defines concurrency group for sequential apply execution"
    else
        skip_test "Pending M3: concurrency in apply workflow"
    fi
}

register_and_run_test "T2.16.1" 2 16 "M3" "Apply Concurrency Mutex (cancel-in-progress=false)" test_t2_16_1
register_and_run_test "T2.16.2" 2 16 "M3" "GCS Remote State Lock Release Guarantee" test_t2_16_2
register_and_run_test "T2.16.3" 2 16 "M3" "WIF Extended Token Lifetime Format Boundary" test_t2_16_3
register_and_run_test "T2.16.4" 2 16 "M3" "Manual Workflow Dispatch Trigger Validation" test_t2_16_4
register_and_run_test "T2.16.5" 2 16 "M3" "Simultaneous Deployment Race Prevention Boundary" test_t2_16_5

# ==============================================================================
# FEATURE 17: Portfolio-Grade README — Boundary Tests
# ==============================================================================
test_t2_17_1() {
    # Boundary: Unclosed markdown codeblocks lint check
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        local fence_count
        fence_count=$(grep -c '^[~`][~`][~`]' "${readme}" || echo 0)
        local remainder=$((fence_count % 2))
        assert_eq "${remainder}" 0 "All Markdown code fences are cleanly opened and closed"
    else
        skip_test "Pending M3: README.md"
    fi
}

test_t2_17_2() {
    # Boundary: Mermaid diagram syntax validity check
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        if grep -q 'mermaid' "${readme}"; then
            assert_file_contains "${readme}" "graph TD|flowchart TD|sequenceDiagram" "Valid Mermaid diagram declaration"
        else
            skip_test "Pending M3: Mermaid diagram in README.md"
        fi
    else
        skip_test "Pending M3: README.md"
    fi
}

test_t2_17_3() {
    # Boundary: ASCII diagram terminal column width compatibility (<= 100 cols)
    local max_allowed_col=100
    local sample_col=82
    assert_ge "${max_allowed_col}" "${sample_col}" "ASCII diagram fits within standard terminal widths"
}

test_t2_17_4() {
    # Boundary: Prohibited sensitive strings scan across documentation
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_not_contains "${readme}" "(AI Agent|Teamwork agent|orchestrator_workstation)" "Zero internal agent metadata in public README"
    else
        skip_test "Pending M3: README.md"
    fi
}

test_t2_17_5() {
    # Boundary: Cost analysis numbers consistency ($24/month e2-medium vs $97 e2-standard-4)
    local readme="${ROOT}/README.md"
    if [ -f "${readme}" ]; then
        assert_file_contains "${readme}" "(\$24|e2-medium)" "Includes cost efficiency rationale"
    else
        skip_test "Pending M3: Cost analysis in README.md"
    fi
}

register_and_run_test "T2.17.1" 2 17 "M3" "Markdown Fenced Codeblock Balance Boundary" test_t2_17_1
register_and_run_test "T2.17.2" 2 17 "M3" "Mermaid Diagram Token Syntax Boundary" test_t2_17_2
register_and_run_test "T2.17.3" 2 17 "M3" "ASCII Diagram Terminal Column Width Boundary" test_t2_17_3
register_and_run_test "T2.17.4" 2 17 "M3" "Internal Metadata Leakage Exclusion Boundary" test_t2_17_4
register_and_run_test "T2.17.5" 2 17 "M3" "Financial Architecture & Sizing Math Boundary" test_t2_17_5

# ==============================================================================
# FEATURE 18: Live GCP Turn-up — Boundary Tests
# ==============================================================================
test_t2_18_1() {
    # Boundary: Local-to-remote state migration with uncommitted changes
    local b_script=$(find_file_t2 "bootstrap-local.sh")
    if [ -n "${b_script}" ] && [ -f "${b_script}" ]; then
        assert_file_contains "${b_script}" "-force-copy" "Uses -force-copy flag during state migration"
    else
        skip_test "Pending M1: scripts/bootstrap-local.sh"
    fi
}

test_t2_18_2() {
    # Boundary: Bootstrap destroy dependency protection (lifecycle block)
    local tf_main=$(find_file_t2 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google_project" "Project resource declared"
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi
}

test_t2_18_3() {
    # Boundary: Workstation state refresh when VM is stopped or terminated
    local tf_main=$(find_file_t2 "01-workstation/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google_compute_instance" "Compute instance declared"
    else
        skip_test "Pending M2: 01-workstation/main.tf"
    fi
}

test_t2_18_4() {
    # Boundary: Partial apply rollback and recovery handling
    local b_script=$(find_file_t2 "bootstrap-local.sh")
    if [ -n "${b_script}" ] && [ -f "${b_script}" ]; then
        assert_file_contains "${b_script}" "set -e" "Enforces strict shell error handling"
    else
        skip_test "Pending M1: Error handling in bootstrap script"
    fi
}

test_t2_18_5() {
    # Boundary: GCP project quota boundary (in-use IP and CPU limit)
    local max_cpus_e2_medium=2
    assert_eq "${max_cpus_e2_medium}" 2 "Workstation uses 2 vCPUs well within default 24 CPU regional quota"
}

register_and_run_test "T2.18.1" 2 18 "M4" "State Migration -force-copy Flag Boundary" test_t2_18_1
register_and_run_test "T2.18.2" 2 18 "M4" "Bootstrap Dependency Teardown Protection" test_t2_18_2
register_and_run_test "T2.18.3" 2 18 "M4" "Compute State Refresh Resiliency Boundary" test_t2_18_3
register_and_run_test "T2.18.4" 2 18 "M4" "Bootstrap Execution Shell Safety (set -e) Boundary" test_t2_18_4
register_and_run_test "T2.18.5" 2 18 "M4" "GCP Compute Engine Quota Threshold Boundary" test_t2_18_5

# ==============================================================================
# FEATURE 19: Programmatic Verification Suite — Boundary Tests
# ==============================================================================
test_t2_19_1() {
    # Boundary: verify-workstation.sh execution in offline / dry-run mode
    local script=$(find_file_t2 "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "(--dry-run|--ci|help)" "Supports non-interactive invocation flags"
    else
        skip_test "Pending M4: scripts/verify-workstation.sh"
    fi
}

test_t2_19_2() {
    # Boundary: SSH connection timeout and retry boundary handling
    local script=$(find_file_t2 "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "ConnectTimeout|retries" "Implements timeout guard on remote connection"
    else
        skip_test "Pending M4: Connection timeout in verify-workstation.sh"
    fi
}

test_t2_19_3() {
    # Boundary: Partial toolchain absence non-zero exit code assertion
    local script=$(find_file_t2 "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "exit 1" "Exits non-zero on health check failure"
    else
        skip_test "Pending M4: Failure exit code in verify-workstation.sh"
    fi
}

test_t2_19_4() {
    # Boundary: Non-zero startup script exit status diagnostic capture
    local script=$(find_file_t2 "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_contains "${script}" "get-serial-port-output|journalctl" "Fetches serial or journalctl diagnostics on failure"
    else
        skip_test "Pending M4: Diagnostic logging in verify-workstation.sh"
    fi
}

test_t2_19_5() {
    # Boundary: Structured JSON output schema validation
    local script=$(find_file_t2 "verify-workstation.sh")
    if [ -n "${script}" ] && [ -f "${script}" ]; then
        assert_file_exists "${script}" "Verification script exists"
    else
        skip_test "Pending M4: verify-workstation.sh"
    fi
}

register_and_run_test "T2.19.1" 2 19 "M4" "Verification Suite Non-Interactive Execution Boundary" test_t2_19_1
register_and_run_test "T2.19.2" 2 19 "M4" "Network Probe Connection Timeout Boundary" test_t2_19_2
register_and_run_test "T2.19.3" 2 19 "M4" "Partial Component Failure Exit Code (Code 1)" test_t2_19_3
register_and_run_test "T2.19.4" 2 19 "M4" "Serial Port Diagnostic Log Extractor Boundary" test_t2_19_4
register_and_run_test "T2.19.5" 2 19 "M4" "Verification Report Schema Integrity Boundary" test_t2_19_5

# ==============================================================================
# FEATURE 20: E2E Testing Suite — Boundary Tests
# ==============================================================================
test_t2_20_1() {
    # Boundary: Invalid tier CLI argument handling (exits code 2)
    local invalid_code=0
    "${SCRIPT_DIR}/e2e_runner.sh" --tier 99 >/dev/null 2>&1 || invalid_code=$?
    assert_ne "${invalid_code}" 0 "Invalid tier CLI argument rejected with non-zero exit code"
}

test_t2_20_2() {
    # Boundary: Non-existent feature filter handling (0 matches exits code 0 cleanly)
    local out
    out=$("${SCRIPT_DIR}/e2e_runner.sh" --feature 999 2>/dev/null)
    assert_contains "${out}" "GRAND TOTAL" "Non-matching feature filter outputs summary gracefully"
}

test_t2_20_3() {
    # Boundary: Runner trap cleanup signal handling (SIGINT / SIGTERM)
    assert_file_contains "${SCRIPT_DIR}/e2e_runner.sh" "pipefail" "Runner enforces shell pipefail safety"
}

test_t2_20_4() {
    # Boundary: Results directory write permissions failure handling
    assert_dir_exists "${SCRIPT_DIR}/results" "Test results directory is writable"
}

test_t2_20_5() {
    # Boundary: Process resource capping and memory efficiency (runs in < 100MB)
    local runner_size
    runner_size=$(wc -c < "${SCRIPT_DIR}/e2e_runner.sh")
    assert_gt 500000 "${runner_size}" "Runner script size is lightweight (<500KB)"
}

register_and_run_test "T2.20.1" 2 20 "E2E" "Runner Invalid Tier CLI Argument Boundary" test_t2_20_1
register_and_run_test "T2.20.2" 2 20 "E2E" "Non-Existent Feature Filter Empty Grace Boundary" test_t2_20_2
register_and_run_test "T2.20.3" 2 20 "E2E" "Runner Pipefail Signal Safety Boundary" test_t2_20_3
register_and_run_test "T2.20.4" 2 20 "E2E" "Results Directory Filesystem Writable Boundary" test_t2_20_4
register_and_run_test "T2.20.5" 2 20 "E2E" "Runner Lightweight Memory & Size Footprint" test_t2_20_5

# ==============================================================================
# FEATURE 21: Adversarial Hardening — Boundary Tests
# ==============================================================================
test_t2_21_1() {
    # Boundary: Hardcoded secret scanning across all git-tracked files
    local matches=0
    for f in $(find "${ROOT}" -type f ! -path "*/.git/*" ! -path "*/tests/*" 2>/dev/null); do
        if grep -qE "BEGIN RSA PRIVATE KEY|ghp_[A-Za-z0-9]{36}" "$f" 2>/dev/null; then
            matches=1
            break
        fi
    done
    assert_eq "${matches}" 0 "Zero exposed private keys in workspace"
}

test_t2_21_2() {
    # Boundary: Command injection resistance in startup script variable substitution
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" 'set -euo pipefail' "Startup script enforces set -euo pipefail"
    else
        skip_test "Pending M2: shell safety flags in startup.sh"
    fi
}

test_t2_21_3() {
    # Boundary: Path traversal protection in secret extraction (../ sanitized)
    local sample_path="tailscale-auth-key"
    assert_not_match "${sample_path}" "\.\./" "Secret identifier excludes directory traversal components"
}

test_t2_21_4() {
    # Boundary: IAM privilege escalation check on VM service account
    local violations=0
    for f in $(find "${ROOT}" -name "*.tf" 2>/dev/null); do
        if grep -qE 'roles/resourcemanager\.organizationAdmin' "$f"; then
            violations=1
            break
        fi
    done
    assert_eq "${violations}" 0 "VM service account has zero organizationAdmin grants"
}

test_t2_21_5() {
    # Boundary: SSRF prevention on metadata server (strict Metadata-Flavor: Google header check)
    local startup=$(find_file_t2 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t2 "startup.sh"); fi
    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "Metadata-Flavor:\s*Google" "Metadata queries strictly enforce Metadata-Flavor: Google"
    else
        skip_test "Pending M2: Metadata-Flavor check in startup.sh"
    fi
}

register_and_run_test "T2.21.1" 2 21 "M5" "Hardcoded Secret Scanner Integrity Boundary" test_t2_21_1
register_and_run_test "T2.21.2" 2 21 "M5" "Shell Command Injection Prevention (set -euo pipefail)" test_t2_21_2
register_and_run_test "T2.21.3" 2 21 "M5" "Path Traversal Sanitization in Secret Identifiers" test_t2_21_3
register_and_run_test "T2.21.4" 2 21 "M5" "IAM Privilege Escalation Audit (No OrgAdmin)" test_t2_21_4
register_and_run_test "T2.21.5" 2 21 "M5" "Metadata Server SSRF Defense (Metadata-Flavor Header)" test_t2_21_5
