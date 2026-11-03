#!/usr/bin/env bash
# ==============================================================================
# e2e_runner.sh — Unified E2E Test Runner Harness
# Production Mobile Cloud Workstation IaC & CI/CD Project
# ==============================================================================
set -uo pipefail

# Find workspace root (parent directory of tests/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Result tracking
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "${RESULTS_DIR}"
RUN_TIMESTAMP="$(date -u +"%Y%m%d_%H%M%SZ")"
LOG_FILE="${RESULTS_DIR}/e2e_results_${RUN_TIMESTAMP}.log"
JSON_FILE="${RESULTS_DIR}/e2e_results_${RUN_TIMESTAMP}.json"

# Terminal formatting
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
else
    C_RESET=""
    C_BOLD=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
fi

# Configuration Defaults
SELECTED_TIER="all"
FILTER_FEATURE=""
TEST_MODE="${TEST_MODE:-auto}" # auto | static | live
STAGE="${STAGE:-all}"          # M1 | M2 | M3 | M4 | M5 | all
VERBOSE="${VERBOSE:-false}"
OUTPUT_JSON=false
DRY_RUN=false

# Metrics accumulators
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
START_TIME_EPOCH=$(date +%s)

# Global test registry and results arrays
declare -a TEST_IDS=()
declare -a TEST_TIERS=()
declare -a TEST_FEATURES=()
declare -a TEST_STAGES=()
declare -a TEST_NAMES=()
declare -a TEST_STATUSES=()
declare -a TEST_DURATIONS=()
declare -a TEST_DIAGNOSTICS=()

# Per-tier counters
declare -A TIER_TOTAL=([1]=0 [2]=0 [3]=0 [4]=0)
declare -A TIER_PASSED=([1]=0 [2]=0 [3]=0 [4]=0)
declare -A TIER_FAILED=([1]=0 [2]=0 [3]=0 [4]=0)
declare -A TIER_SKIPPED=([1]=0 [2]=0 [3]=0 [4]=0)

# ------------------------------------------------------------------------------
# Logging & Output Helpers
# ------------------------------------------------------------------------------
log() {
    local msg="$1"
    echo -e "${msg}" | tee -a "${LOG_FILE}"
}

log_verbose() {
    local msg="$1"
    if [ "${VERBOSE}" = "true" ]; then
        echo -e "    ${C_CYAN}[VERBOSE]${C_RESET} ${msg}" | tee -a "${LOG_FILE}"
    else
        echo -e "    [VERBOSE] ${msg}" >> "${LOG_FILE}"
    fi
}

show_help() {
    cat << EOF
Mobile Workstation E2E Test Runner Harness

Usage: ./tests/e2e_runner.sh [OPTIONS]

Options:
  --all                     Run all test tiers (Tiers 1-4) [default]
  --tier <1|2|3|4>          Run only the specified test tier
  --feature <1..21>         Filter tests by Feature ID (1 to 21)
  --mode <auto|static|live> Execution mode (default: auto)
  --stage <M1..M5|all>      Milestone stage filter (default: all)
  --verbose, -v             Enable verbose diagnostics
  --json                    Output JSON report to stdout in addition to file
  --dry-run                 Enumerate matching tests without executing
  --help, -h                Show this help message

Environment Variables:
  TEST_MODE=auto|static|live
  STAGE=M1|M2|M3|M4|M5|all
  VERBOSE=true|false
  WORKSPACE_ROOT=<path>
EOF
}

# ------------------------------------------------------------------------------
# CLI Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            SELECTED_TIER="all"
            shift
            ;;
        --tier)
            if [[ "$2" != "1" && "$2" != "2" && "$2" != "3" && "$2" != "4" && "$2" != "all" ]]; then
                echo "Error: Invalid tier '$2'. Must be 1, 2, 3, 4, or all" >&2
                exit 2
            fi
            SELECTED_TIER="$2"
            shift 2
            ;;
        --feature)
            FILTER_FEATURE="$2"
            shift 2
            ;;
        --mode)
            TEST_MODE="$2"
            shift 2
            ;;
        --stage)
            STAGE="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 2
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Assertion Library
# ------------------------------------------------------------------------------
CURRENT_ASSERT_FAIL=""

assert_eq() {
    local actual="$1"
    local expected="$2"
    local desc="${3:-Assertion}"
    if [ "${actual}" != "${expected}" ]; then
        CURRENT_ASSERT_FAIL="Expected '${expected}', but got '${actual}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: '${actual}' == '${expected}' (OK)"
    return 0
}

assert_ne() {
    local actual="$1"
    local unexpected="$2"
    local desc="${3:-Assertion}"
    if [ "${actual}" = "${unexpected}" ]; then
        CURRENT_ASSERT_FAIL="Value '${actual}' should NOT equal unexpected '${unexpected}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: '${actual}' != '${unexpected}' (OK)"
    return 0
}

assert_match() {
    local actual="$1"
    local pattern="$2"
    local desc="${3:-Assertion}"
    if ! [[ "${actual}" =~ ${pattern} ]]; then
        CURRENT_ASSERT_FAIL="Value '${actual}' does not match pattern '${pattern}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: '${actual}' matches pattern (OK)"
    return 0
}

assert_not_match() {
    local actual="$1"
    local pattern="$2"
    local desc="${3:-Assertion}"
    if [[ "${actual}" =~ ${pattern} ]]; then
        CURRENT_ASSERT_FAIL="Value '${actual}' should NOT match pattern '${pattern}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: value does not match pattern (OK)"
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="${3:-Assertion}"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        CURRENT_ASSERT_FAIL="Haystack does not contain '${needle}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: substring found (OK)"
    return 0
}

assert_file_exists() {
    local filepath="$1"
    local desc="${2:-File existence check}"
    if [ ! -f "${filepath}" ]; then
        CURRENT_ASSERT_FAIL="File '${filepath}' does not exist (${desc})"
        return 1
    fi
    log_verbose "${desc}: file '${filepath}' exists (OK)"
    return 0
}

assert_dir_exists() {
    local dirpath="$1"
    local desc="${2:-Directory existence check}"
    if [ ! -d "${dirpath}" ]; then
        CURRENT_ASSERT_FAIL="Directory '${dirpath}' does not exist (${desc})"
        return 1
    fi
    log_verbose "${desc}: directory '${dirpath}' exists (OK)"
    return 0
}

assert_file_contains() {
    local filepath="$1"
    local pattern="$2"
    local desc="${3:-File content check}"
    if [ ! -f "${filepath}" ]; then
        CURRENT_ASSERT_FAIL="Cannot check content: file '${filepath}' does not exist (${desc})"
        return 1
    fi
    if ! grep -qE -- "${pattern}" "${filepath}" 2>/dev/null; then
        CURRENT_ASSERT_FAIL="File '${filepath}' does not contain regex '${pattern}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: file '${filepath}' contains pattern '${pattern}' (OK)"
    return 0
}

assert_file_not_contains() {
    local filepath="$1"
    local pattern="$2"
    local desc="${3:-File negative content check}"
    if [ ! -f "${filepath}" ]; then
        CURRENT_ASSERT_FAIL="File '${filepath}' does not exist (${desc})"
        return 1
    fi
    if grep -qE -- "${pattern}" "${filepath}" 2>/dev/null; then
        CURRENT_ASSERT_FAIL="File '${filepath}' unexpectedly contains prohibited regex '${pattern}' (${desc})"
        return 1
    fi
    log_verbose "${desc}: file '${filepath}' excludes prohibited pattern '${pattern}' (OK)"
    return 0
}

assert_exit_code() {
    local expected_code="$1"
    local cmd="$2"
    local desc="${3:-Command exit code check}"
    local actual_code=0
    eval "${cmd}" >/dev/null 2>&1 || actual_code=$?
    if [ "${actual_code}" -ne "${expected_code}" ]; then
        CURRENT_ASSERT_FAIL="Command '${cmd}' exited with code ${actual_code}, expected ${expected_code} (${desc})"
        return 1
    fi
    log_verbose "${desc}: command exited with code ${actual_code} (OK)"
    return 0
}

assert_gt() {
    local actual="$1"
    local minimum="$2"
    local desc="${3:-Numeric comparison}"
    if [ "${actual}" -le "${minimum}" ]; then
        CURRENT_ASSERT_FAIL="Expected value ${actual} to be greater than ${minimum} (${desc})"
        return 1
    fi
    log_verbose "${desc}: ${actual} > ${minimum} (OK)"
    return 0
}

assert_ge() {
    local actual="$1"
    local minimum="$2"
    local desc="${3:-Numeric comparison}"
    if [ "${actual}" -lt "${minimum}" ]; then
        CURRENT_ASSERT_FAIL="Expected value ${actual} to be greater than or equal to ${minimum} (${desc})"
        return 1
    fi
    log_verbose "${desc}: ${actual} >= ${minimum} (OK)"
    return 0
}

# ------------------------------------------------------------------------------
# Test Registration & Dispatch Engine
# ------------------------------------------------------------------------------
register_and_run_test() {
    local test_id="$1"
    local tier="$2"
    local feature_id="$3"
    local milestone_stage="$4"
    local test_name="$5"
    local test_fn="$6"

    # Filter by Tier
    if [ "${SELECTED_TIER}" != "all" ] && [ "${SELECTED_TIER}" != "${tier}" ]; then
        return 0
    fi

    # Filter by Feature ID
    if [ -n "${FILTER_FEATURE}" ] && [ "${FILTER_FEATURE}" != "${feature_id}" ]; then
        return 0
    fi

    # Filter by Milestone Stage (if not "all")
    if [ "${STAGE}" != "all" ] && [ "${STAGE}" != "${milestone_stage}" ]; then
        # Skip if test belongs to a later stage
        return 0
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TIER_TOTAL[${tier}]=$((TIER_TOTAL[${tier}] + 1))

    if [ "${DRY_RUN}" = "true" ]; then
        echo -e "[DRY-RUN] Tier ${tier} | ${test_id} | Feature ${feature_id} | Stage ${milestone_stage} | ${test_name}"
        return 0
    fi

    CURRENT_ASSERT_FAIL=""
    local t_start
    t_start=$(date +%s%N 2>/dev/null || echo 0)

    # Execute test function safely
    local status="PASS"
    local diagnostic=""

    # Run the test function
    if ! "${test_fn}"; then
        if [ -n "${CURRENT_ASSERT_FAIL}" ]; then
            diagnostic="${CURRENT_ASSERT_FAIL}"
            status="FAIL"
        else
            diagnostic="Test function returned non-zero"
            status="FAIL"
        fi
    fi

    # Check for SKIP condition explicitly signaled by test
    if [[ "${CURRENT_ASSERT_FAIL}" =~ ^SKIP: ]]; then
        status="SKIP"
        diagnostic="${CURRENT_ASSERT_FAIL#SKIP: }"
    fi

    local t_end
    t_end=$(date +%s%N 2>/dev/null || echo 0)
    local duration_ms=0
    if [ "${t_start}" -ne 0 ] && [ "${t_end}" -ne 0 ]; then
        duration_ms=$(( (t_end - t_start) / 1000000 ))
    fi

    # Accumulate results
    if [ "${status}" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TIER_PASSED[${tier}]=$((TIER_PASSED[${tier}] + 1))
        log "  ${C_GREEN}[PASS]${C_RESET} ${C_BOLD}${test_id}${C_RESET} (F${feature_id}): ${test_name} (${duration_ms}ms)"
    elif [ "${status}" = "SKIP" ]; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
        TIER_SKIPPED[${tier}]=$((TIER_SKIPPED[${tier}] + 1))
        log "  ${C_YELLOW}[SKIP]${C_RESET} ${C_BOLD}${test_id}${C_RESET} (F${feature_id}): ${test_name} — ${diagnostic}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TIER_FAILED[${tier}]=$((TIER_FAILED[${tier}] + 1))
        log "  ${C_RED}[FAIL]${C_RESET} ${C_BOLD}${test_id}${C_RESET} (F${feature_id}): ${test_name}"
        log "         ${C_RED}Reason: ${diagnostic}${C_RESET}"
    fi

    # Store for reporting
    TEST_IDS+=("${test_id}")
    TEST_TIERS+=("${tier}")
    TEST_FEATURES+=("${feature_id}")
    TEST_STAGES+=("${milestone_stage}")
    TEST_NAMES+=("${test_name}")
    TEST_STATUSES+=("${status}")
    TEST_DURATIONS+=("${duration_ms}")
    TEST_DIAGNOSTICS+=("${diagnostic}")
}

skip_test() {
    local reason="$1"
    CURRENT_ASSERT_FAIL="SKIP: ${reason}"
    return 0
}

# ------------------------------------------------------------------------------
# Test Suite Loader & Execution Header
# ------------------------------------------------------------------------------
log "${C_BOLD}========================================================================${C_RESET}"
log "${C_BOLD}  Mobile Workstation IaC & CI/CD — E2E Test Suite Execution${C_RESET}"
log "${C_BOLD}========================================================================${C_RESET}"
log "Workspace: ${WORKSPACE_ROOT}"
log "Test Mode: ${TEST_MODE} | Stage: ${STAGE} | Tier: ${SELECTED_TIER} | Verbose: ${VERBOSE}"
log "Started at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log ""

# Source Tier test definition files
if [ "${SELECTED_TIER}" = "all" ] || [ "${SELECTED_TIER}" = "1" ]; then
    TIER1_FILE="${SCRIPT_DIR}/tier1_feature_tests.sh"
    if [ -f "${TIER1_FILE}" ]; then
        log "${C_BLUE}--- Executing Tier 1: Isolated Feature Tests (Features 1..21) ---${C_RESET}"
        # shellcheck source=/dev/null
        source "${TIER1_FILE}"
        log ""
    fi
fi

if [ "${SELECTED_TIER}" = "all" ] || [ "${SELECTED_TIER}" = "2" ]; then
    TIER2_FILE="${SCRIPT_DIR}/tier2_boundary_tests.sh"
    if [ -f "${TIER2_FILE}" ]; then
        log "${C_BLUE}--- Executing Tier 2: Boundary & Corner Case Tests (Features 1..21) ---${C_RESET}"
        # shellcheck source=/dev/null
        source "${TIER2_FILE}"
        log ""
    fi
fi

if [ "${SELECTED_TIER}" = "all" ] || [ "${SELECTED_TIER}" = "3" ]; then
    TIER3_FILE="${SCRIPT_DIR}/tier3_integration_tests.sh"
    if [ -f "${TIER3_FILE}" ]; then
        log "${C_BLUE}--- Executing Tier 3: Cross-Feature Integration Scenarios ---${C_RESET}"
        # shellcheck source=/dev/null
        source "${TIER3_FILE}"
        log ""
    fi
fi

if [ "${SELECTED_TIER}" = "all" ] || [ "${SELECTED_TIER}" = "4" ]; then
    TIER4_FILE="${SCRIPT_DIR}/tier4_workload_tests.sh"
    if [ -f "${TIER4_FILE}" ]; then
        log "${C_BLUE}--- Executing Tier 4: Realistic Developer Workloads ---${C_RESET}"
        # shellcheck source=/dev/null
        source "${TIER4_FILE}"
        log ""
    fi
fi

END_TIME_EPOCH=$(date +%s)
TOTAL_DURATION=$((END_TIME_EPOCH - START_TIME_EPOCH))

# ------------------------------------------------------------------------------
# Summary Table & Reporting
# ------------------------------------------------------------------------------
log "${C_BOLD}========================================================================${C_RESET}"
log "${C_BOLD}                          Test Execution Summary                        ${C_RESET}"
log "${C_BOLD}========================================================================${C_RESET}"
printf "%-12s | %-10s | %-10s | %-10s | %-10s\n" "Tier" "Total" "Passed" "Failed" "Skipped"
log "------------------------------------------------------------------------"

for t in 1 2 3 4; do
    if [ "${SELECTED_TIER}" = "all" ] || [ "${SELECTED_TIER}" = "${t}" ]; then
        tier_label="Tier ${t}"
        case "$t" in
            1) tier_label="Tier 1 (Feat)" ;;
            2) tier_label="Tier 2 (Bound)" ;;
            3) tier_label="Tier 3 (Integ)" ;;
            4) tier_label="Tier 4 (Workl)" ;;
        esac
        printf "%-14s | %-10d | %-10d | %-10d | %-10d\n" \
            "${tier_label}" "${TIER_TOTAL[$t]}" "${TIER_PASSED[$t]}" "${TIER_FAILED[$t]}" "${TIER_SKIPPED[$t]}" | tee -a "${LOG_FILE}"
    fi
done

log "------------------------------------------------------------------------"
printf "${C_BOLD}%-14s | %-10d | %-10d | %-10d | %-10d${C_RESET}\n" \
    "GRAND TOTAL" "${TOTAL_TESTS}" "${PASSED_TESTS}" "${FAILED_TESTS}" "${SKIPPED_TESTS}" | tee -a "${LOG_FILE}"
log "Total Duration: ${TOTAL_DURATION}s"
log "Artifact Log:   ${LOG_FILE}"

# Build JSON report
python3 - << EOF
import json, sys

results = []
test_ids = """${TEST_IDS[*]:-}""".split()
test_tiers = """${TEST_TIERS[*]:-}""".split()
test_features = """${TEST_FEATURES[*]:-}""".split()
test_stages = """${TEST_STAGES[*]:-}""".split()
test_statuses = """${TEST_STATUSES[*]:-}""".split()
test_durations = """${TEST_DURATIONS[*]:-}""".split()

for i in range(len(test_ids)):
    results.append({
        "id": test_ids[i],
        "tier": int(test_tiers[i]) if test_tiers else 0,
        "feature_id": int(test_features[i]) if test_features else 0,
        "stage": test_stages[i] if test_stages else "",
        "status": test_statuses[i] if test_statuses else "",
        "duration_ms": int(test_durations[i]) if test_durations else 0
    })

data = {
    "summary": {
        "total": ${TOTAL_TESTS},
        "passed": ${PASSED_TESTS},
        "failed": ${FAILED_TESTS},
        "skipped": ${SKIPPED_TESTS},
        "duration_seconds": ${TOTAL_DURATION},
        "exit_code": 1 if ${FAILED_TESTS} > 0 else 0
    },
    "environment": {
        "test_mode": "${TEST_MODE}",
        "stage": "${STAGE}",
        "tier_filter": "${SELECTED_TIER}",
        "feature_filter": "${FILTER_FEATURE}",
        "workspace": "${WORKSPACE_ROOT}",
        "timestamp": "${RUN_TIMESTAMP}"
    },
    "results": results
}

with open("${JSON_FILE}", "w") as f:
    json.dump(data, f, indent=2)

if "${OUTPUT_JSON}" == "true":
    print(json.dumps(data, indent=2))
EOF

log "Artifact JSON:  ${JSON_FILE}"

if [ "${FAILED_TESTS}" -eq 0 ]; then
    log "\n${C_GREEN}${C_BOLD}✓ SUCCESS: All ${PASSED_TESTS} executed tests passed cleanly.${C_RESET}\n"
    exit 0
else
    log "\n${C_RED}${C_BOLD}✗ FAILURE: ${FAILED_TESTS} test(s) failed.${C_RESET}\n"
    exit 1
fi
