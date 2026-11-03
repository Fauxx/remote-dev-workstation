#!/usr/bin/env bash
# ==============================================================================
# tier4_workload_tests.sh — Realistic End-to-End Developer Workflows
# Validates complete lifecycle workflows from provisioning to developer coding
# ==============================================================================
set -uo pipefail

ROOT="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

find_file_t4() {
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

# ------------------------------------------------------------------------------
# WORKLOAD 1: End-to-End Workstation Provisioning Lifecycle
# ------------------------------------------------------------------------------
test_t4_workload_1() {
    # 1. Verify 00-bootstrap directory and configuration validity
    local b_dir="${ROOT}/terraform/00-bootstrap"
    if [ ! -d "${b_dir}" ]; then b_dir="${ROOT}/00-bootstrap"; fi
    if [ ! -d "${b_dir}" ]; then
        skip_test "Pending M1: 00-bootstrap directory"
        return 0
    fi

    # 2. Assert Terraform syntax validation on 00-bootstrap
    local fmt_exit=0
    terraform -chdir="${b_dir}" fmt -check -diff >/dev/null 2>&1 || fmt_exit=$?
    assert_eq "${fmt_exit}" 0 "00-bootstrap conforms to terraform fmt standard"

    # 3. Assert bootstrap migration automation script exists and has execution bit
    local b_script=$(find_file_t4 "bootstrap-local.sh")
    if [ -n "${b_script}" ] && [ -f "${b_script}" ]; then
        assert_file_exists "${b_script}" "bootstrap-local.sh exists" && \
        assert_file_contains "${b_script}" "gh variable set" "Populates GitHub repository variables automatically"
    else
        skip_test "Pending M1: scripts/bootstrap-local.sh"
    fi
}

# ------------------------------------------------------------------------------
# WORKLOAD 2: Zero-Trust Developer Shell Experience Roundtrip
# ------------------------------------------------------------------------------
test_t4_workload_2() {
    # 1. Assert Tailscale SSH and defensive tmux auto-attach in startup.sh
    local startup=$(find_file_t4 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t4 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale up [^\n]*--ssh" "Tailscale SSH server initialized" && \
        assert_file_contains "${startup}" "tmux new-session -A -s main|tmux new-session -s dev" "tmux auto-attach session creates/attaches persistent session" && \
        assert_file_contains "${startup}" "\[\s*-t\s*[01]\s*\]" "Guards against terminal hijacking on non-interactive SSH"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# WORKLOAD 3: Full-Stack Code Development Workflow
# ------------------------------------------------------------------------------
test_t4_workload_3() {
    # 1. Verify developer toolchain configuration
    local startup=$(find_file_t4 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t4 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "nodejs" "Node.js toolchain provisioned" && \
        assert_file_contains "${startup}" "python3" "Python 3 environment provisioned" && \
        assert_file_contains "${startup}" "antigravity" "Antigravity CLI (agy) provisioned" && \
        assert_file_contains "${startup}" "FireMonitoringSystem" "FireMonitoringSystem project repository cloned into workspace"
    else
        skip_test "Pending M2: Developer toolchain in startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# WORKLOAD 4: Keyless CI/CD PR & Deployment Lifecycle
# ------------------------------------------------------------------------------
test_t4_workload_4() {
    local wf_plan=$(find_file_t4 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf_plan}" ]; then wf_plan=$(find_file_t4 ".github/workflows/tf-plan.yml"); fi
    local wf_apply=$(find_file_t4 ".github/workflows/terraform-apply.yml")
    if [ -z "${wf_apply}" ]; then wf_apply=$(find_file_t4 ".github/workflows/tf-apply.yml"); fi

    if [ -n "${wf_plan}" ] && [ -f "${wf_plan}" ] && [ -n "${wf_apply}" ] && [ -f "${wf_apply}" ]; then
        # PR Plan Workflow Check
        assert_file_contains "${wf_plan}" "pull_request:" "PR workflow listens to pull_request events" && \
        assert_file_contains "${wf_plan}" "google-github-actions/auth" "Authenticates via keyless WIF" && \
        assert_file_contains "${wf_plan}" "terraform plan" "Executes automated plan"

        # Push to Main Apply Workflow Check
        assert_file_contains "${wf_apply}" "push:" "Apply workflow listens to push to main" && \
        assert_file_contains "${wf_apply}" "cancel-in-progress:\s*false" "Apply workflow enforces mutual exclusion" && \
        assert_file_contains "${wf_apply}" "terraform apply" "Executes automated apply"
    else
        skip_test "Pending M3: CI/CD Workflows (.github/workflows/)"
    fi
}

# ------------------------------------------------------------------------------
# WORKLOAD 5: Security Posture, Compliance & Zero-Charge Audit
# ------------------------------------------------------------------------------
test_t4_workload_5() {
    # 1. Prohibit service account keys in any Terraform configuration
    local sa_keys_count=0
    for tf in $(find "${ROOT}" -name "*.tf" 2>/dev/null); do
        if grep -qE 'resource\s+"google_service_account_key"' "$tf"; then
            sa_keys_count=$((sa_keys_count + 1))
        fi
    done
    assert_eq "${sa_keys_count}" 0 "Zero long-lived service account keys across all Terraform configurations"

    # 2. Strict Uniform Bucket Level Access compliance
    local tf_main=$(find_file_t4 "00-bootstrap/main.tf")
    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "uniform_bucket_level_access\s*=\s*true" "Enforces uniform bucket level access Org Policy"
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi

    # 3. Defensive clean teardown capability
    local teardown=$(find_file_t4 "teardown.sh")
    if [ -n "${teardown}" ] && [ -f "${teardown}" ]; then
        assert_file_contains "${teardown}" "destroy" "Provides automated teardown to prevent cloud charges"
    else
        log_verbose "Teardown script pending M4"
    fi
}

register_and_run_test "T4.1.1" 4 18 "M1" "Workload 1: End-to-End Workstation Infrastructure Lifecycle" test_t4_workload_1
register_and_run_test "T4.2.1" 4 10 "M2" "Workload 2: Zero-Trust Developer Shell Experience Roundtrip" test_t4_workload_2
register_and_run_test "T4.3.1" 4 13 "M2" "Workload 3: Full-Stack Code Development Workflow" test_t4_workload_3
register_and_run_test "T4.4.1" 4 15 "M3" "Workload 4: Keyless CI/CD PR & Deployment Lifecycle" test_t4_workload_4
register_and_run_test "T4.5.1" 4 21 "M5" "Workload 5: Security Posture, Compliance & Zero-Charge Audit" test_t4_workload_5
