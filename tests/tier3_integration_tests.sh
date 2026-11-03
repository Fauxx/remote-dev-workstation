#!/usr/bin/env bash
# ==============================================================================
# tier3_integration_tests.sh — Cross-Feature Pairwise Integration Test Scenarios
# Validates interface contracts, cross-module data flow, and runtime handshakes
# ==============================================================================
set -uo pipefail

ROOT="${WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

find_file_t3() {
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
# SCENARIO 1: Workload Identity Federation (F5) ↔ GitHub Actions Workflows (F15/F16)
# ------------------------------------------------------------------------------
test_t3_scenario_1() {
    local tf_main=$(find_file_t3 "00-bootstrap/main.tf")
    local wf_plan=$(find_file_t3 ".github/workflows/terraform-plan.yml")
    if [ -z "${wf_plan}" ]; then wf_plan=$(find_file_t3 ".github/workflows/tf-plan.yml"); fi

    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        # 1. Assert WIF provider in bootstrap matches token.actions.githubusercontent.com
        assert_file_contains "${tf_main}" "token\.actions\.githubusercontent\.com" "WIF issuer targets GitHub Actions OIDC" && \
        assert_file_contains "${tf_main}" "assertion\.repository" "WIF maps repository assertion"
        
        # 2. If workflow exists, verify consumer contract
        if [ -n "${wf_plan}" ] && [ -f "${wf_plan}" ]; then
            assert_file_contains "${wf_plan}" "google-github-actions/auth" "Workflow consumes WIF authentication"
        fi
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 2: 00-Bootstrap Outputs (F2/F4/F5) ↔ 01-Workstation Data Ingestion (F7/F8)
# ------------------------------------------------------------------------------
test_t3_scenario_2() {
    local b_out=$(find_file_t3 "00-bootstrap/outputs.tf")
    local w_main=$(find_file_t3 "01-workstation/main.tf")

    if [ -n "${b_out}" ] && [ -f "${b_out}" ]; then
        assert_file_contains "${b_out}" "project_id" "Bootstrap exports project_id" && \
        assert_file_contains "${b_out}" "state_bucket_name" "Bootstrap exports state_bucket_name"

        if [ -n "${w_main}" ] && [ -f "${w_main}" ]; then
            assert_file_contains "${w_main}" "terraform_remote_state" "Workstation ingests bootstrap remote state"
        else
            log_verbose "Workstation IaC pending M2; contract verified on producer side"
        fi
    else
        skip_test "Pending M1: 00-bootstrap/outputs.tf"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 3: Secret Manager Vault (F6) ↔ VM Startup Script Extraction (F10/F12)
# ------------------------------------------------------------------------------
test_t3_scenario_3() {
    local tf_main=$(find_file_t3 "00-bootstrap/main.tf")
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google_secret_manager_secret" "Secrets provisioned in Secret Manager" && \
        assert_file_contains "${tf_main}" "secretAccessor" "secretAccessor IAM role granted"

        if [ -n "${startup}" ] && [ -f "${startup}" ]; then
            assert_file_contains "${startup}" "secretmanager\.googleapis\.com" "Startup script queries Secret Manager REST API"
        else
            log_verbose "Startup script pending M2; contract verified on Secret Manager provider side"
        fi
    else
        skip_test "Pending M1: Secret Manager definition"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 4: Custom VPC Subnet (F7) ↔ Multi-Port Firewall Rules (F7/F10/F11)
# ------------------------------------------------------------------------------
test_t3_scenario_4() {
    local w_main=$(find_file_t3 "01-workstation/main.tf")

    if [ -n "${w_main}" ] && [ -f "${w_main}" ]; then
        assert_file_contains "${w_main}" "google_compute_network" "VPC network defined" && \
        assert_file_contains "${w_main}" "60000-61000" "Mosh firewall rule bounds match network" && \
        assert_file_contains "${w_main}" "41641" "Tailscale firewall bounds match network"
    else
        skip_test "Pending M2: 01-workstation/main.tf"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 5: Tailscale SSH Daemon (F10) ↔ tmux Safe Auto-Attach (F11)
# ------------------------------------------------------------------------------
test_t3_scenario_5() {
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "tailscale up [^\n]*--ssh" "Tailscale SSH server enabled" && \
        assert_file_contains "${startup}" "tmux new-session" "tmux session automatically invoked on login" && \
        assert_file_contains "${startup}" "\[\s*-t\s*[01]\s*\]" "Defensive TTY guard isolates tmux from non-interactive commands"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 6: Antigravity CLI Execution (F13) ↔ FireMonitoringSystem Workspace (F14)
# ------------------------------------------------------------------------------
test_t3_scenario_6() {
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "antigravity\.google/cli/install\.sh" "Installs agy CLI" && \
        assert_file_contains "${startup}" "FireMonitoringSystem" "Clones FireMonitoringSystem workspace"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 7: Node.js 22 LTS (F13) + Python 3 (F13) Environment Coexistence
# ------------------------------------------------------------------------------
test_t3_scenario_7() {
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "node_22\.x" "Configures Node.js 22 LTS" && \
        assert_file_contains "${startup}" "python3-venv" "Configures Python 3 virtual environment"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 8: 4GB Swapfile (F9) ↔ Linux Sysctl Kernel Tuning (F9) Integration
# ------------------------------------------------------------------------------
test_t3_scenario_8() {
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "/swapfile" "Allocates /swapfile" && \
        assert_file_contains "${startup}" "vm\.swappiness" "Tunes swappiness for low-memory absorption" && \
        assert_file_contains "${startup}" "vm\.vfs_cache_pressure" "Tunes vfs_cache_pressure"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 9: CI/CD Apply Concurrency (F16) ↔ GCS Remote State Locking (F4)
# ------------------------------------------------------------------------------
test_t3_scenario_9() {
    local tf_main=$(find_file_t3 "00-bootstrap/main.tf")
    local wf_apply=$(find_file_t3 ".github/workflows/terraform-apply.yml")
    if [ -z "${wf_apply}" ]; then wf_apply=$(find_file_t3 ".github/workflows/tf-apply.yml"); fi

    if [ -n "${tf_main}" ] && [ -f "${tf_main}" ]; then
        assert_file_contains "${tf_main}" "google_storage_bucket" "Storage bucket provides native GCS mutual exclusion"

        if [ -n "${wf_apply}" ] && [ -f "${wf_apply}" ]; then
            assert_file_contains "${wf_apply}" "cancel-in-progress:\s*false" "Workflow prevents interrupting active state lock holder"
        fi
    else
        skip_test "Pending M1: 00-bootstrap/main.tf"
    fi
}

# ------------------------------------------------------------------------------
# SCENARIO 10: Git Global Identity (F12) ↔ Cloned Repository Remote Push URL (F14)
# ------------------------------------------------------------------------------
test_t3_scenario_10() {
    local startup=$(find_file_t3 "01-workstation/startup.sh")
    if [ -z "${startup}" ]; then startup=$(find_file_t3 "startup.sh"); fi

    if [ -n "${startup}" ] && [ -f "${startup}" ]; then
        assert_file_contains "${startup}" "git config --global user\.name" "Sets git committer name" && \
        assert_file_contains "${startup}" "git remote set-url --push|git@github\.com" "Configures git push remote with SSH URL"
    else
        skip_test "Pending M2: scripts/startup.sh"
    fi
}

register_and_run_test "T3.1.1" 3 5 "M3" "Integration: WIF OIDC Token Provider ↔ GitHub Actions Workflows" test_t3_scenario_1
register_and_run_test "T3.2.1" 3 2 "M2" "Integration: 00-Bootstrap Outputs ↔ 01-Workstation Data Ingestion" test_t3_scenario_2
register_and_run_test "T3.3.1" 3 6 "M2" "Integration: Secret Manager Vault ↔ VM Startup Script Extraction" test_t3_scenario_3
register_and_run_test "T3.4.1" 3 7 "M2" "Integration: Custom VPC Subnet ↔ Multi-Port Firewall Rules" test_t3_scenario_4
register_and_run_test "T3.5.1" 3 10 "M2" "Integration: Tailscale SSH Daemon ↔ Safe tmux Auto-Attach Handshake" test_t3_scenario_5
register_and_run_test "T3.6.1" 3 13 "M2" "Integration: Antigravity CLI Execution ↔ FireMonitoringSystem Workspace" test_t3_scenario_6
register_and_run_test "T3.7.1" 3 13 "M2" "Integration: Node.js 22 LTS ↔ Python 3 Environment Coexistence" test_t3_scenario_7
register_and_run_test "T3.8.1" 3 9 "M2" "Integration: 4GB Swapfile ↔ Linux Sysctl Memory Tuning" test_t3_scenario_8
register_and_run_test "T3.9.1" 3 16 "M3" "Integration: CI/CD Apply Concurrency ↔ GCS Remote State Locking" test_t3_scenario_9
register_and_run_test "T3.10.1" 3 12 "M2" "Integration: Git Identity Pre-Seeding ↔ Workspace Push Remote Origin" test_t3_scenario_10
