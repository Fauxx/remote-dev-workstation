# Mobile Workstation E2E Testing Framework Infrastructure (`TEST_INFRA.md`)

**Project**: Remote Dev Workstation (Production IaC & CI/CD)  
**Track**: E2E Testing Track  
**Document Version**: 1.0.0  
**Author**: Test Writer Subagent (`test_writer_ws_e2e_1`)  
**Target Repository**: `Fauxx/remote-dev-workstation`  
**Workspace Path**: `~/teamwork_projects/remote_dev_workstation`  

---

## 1. Executive Overview

This document specifies the authoritative test architecture, runner harness, assertion conventions, and execution protocols for the end-to-end (E2E) testing track of the Mobile Workstation project.

The testing framework provides **opaque-box, requirement-driven verification** of the entire workstation lifecycle:
1. **GitHub Repository & CI/CD Layer**: Public repository layout, Workload Identity Federation (WIF) OIDC claim validation, PR plan workflow with sticky commenting, and push-to-main apply with state lock mutual exclusion.
2. **Layered Terraform IaC**: `00-bootstrap` (GCP Project, APIs, uniform bucket level access GCS state, WIF pool, Secret Manager, SAs) and `01-workstation` (VPC network, firewall rules, `e2-medium` 50GB VM, IAM bindings).
3. **VM Startup & Tooling Provisioning**: 4GB persistent swapfile with sysctl tuning, Tailscale daemon with zero-trust Tailscale SSH, Mosh UDP firewalling, defensive tmux auto-attach (`[ -t 0 ]` TTY guards), Node.js 22 LTS, Python 3 + venv, Antigravity CLI (`agy` v1.4.12), and cloned `FireMonitoringSystem` workspace.
4. **Portfolio-Grade Documentation & Verification**: Architecture diagrams, security model comparison, programmatic verification suite (`scripts/verify-workstation.sh`), and disaster recovery runbooks.

---

## 2. Test Architecture & Tier Taxonomy

The test framework is organized into five complementary tiers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      E2E Test Runner Harness                           │
│                     (tests/e2e_runner.sh)                              │
└────────────────────────────────────────────────────────────────────────┘
     │                    │                     │                   │
     ▼                    ▼                     ▼                   ▼
┌──────────────┐   ┌──────────────┐     ┌──────────────┐    ┌──────────────┐
│    Tier 1    │   │    Tier 2    │     │    Tier 3    │    │    Tier 4    │
│   Feature    │   │   Boundary   │     │ Integration  │    │   Workload   │
│ (Isolated)   │   │  & Corners   │     │  (Pairwise)  │    │  (Workflows) │
│ >= 105 Tests │   │ >= 105 Tests │     │  >= 10 Tests │    │  >= 5 Tests  │
└──────────────┘   └──────────────┘     └──────────────┘    └──────────────┘
                                                                    │
                                                                    ▼
                                                            ┌──────────────┐
                                                            │    Tier 5    │
                                                            │  Adversarial │
                                                            │  Hardening   │
                                                            │ (Milestone 5)│
                                                            └──────────────┘
```

### 2.1 Tier Definitions

| Tier | Name | Target Scope | Min Tests | Executable Script |
|------|------|--------------|-----------|-------------------|
| **Tier 1** | **Feature Tests** | Isolated validation of every single feature across functional paths | 105 (5/feature × 21) | `tests/tier1_feature_tests.sh` |
| **Tier 2** | **Boundary Tests** | Limit testing, null inputs, quota boundaries, idempotency, failure recovery | 105 (5/feature × 21) | `tests/tier2_boundary_tests.sh` |
| **Tier 3** | **Integration Tests**| Cross-module interactions, data contracts between bootstrap and workstation | 10 | `tests/tier3_integration_tests.sh` |
| **Tier 4** | **Workload Tests** | End-to-end realistic developer scenarios and complete lifecycle workflows | 5 | `tests/tier4_workload_tests.sh` |
| **Tier 5** | **Adversarial Hardening** | Stress-testing, fault injection, security violation scanning | Evaluated in M5 | Evaluated during Milestone 5 |

---

## 3. Progressive Testability Model

To guarantee test execution across all stages of project delivery without premature failures or facade mocks, the framework implements **Progressive Testability**:

1. **Stage Awareness**: Tests detect the current milestone stage (`STAGE=M1`, `STAGE=M2`, `STAGE=M3`, `STAGE=M4`, `STAGE=M5` or `STAGE=all`).
2. **Dual-Mode Verification**:
   - **Static / Specification Verification (`TEST_MODE=static`)**: Validates IaC schemas, HCL blocks, policy constraints, startup scripts, shell syntax, workflow configurations, and documentation without requiring live cloud infrastructure.
   - **Live / Runtime Verification (`TEST_MODE=live`)**: Queries Google Cloud APIs (`gcloud`), GCP Compute Engine metadata, GCS buckets, Secret Manager, Tailscale daemons, and SSH connections on deployed infrastructure.
   - **Auto Mode (`TEST_MODE=auto`, default)**: Dynamically checks available assets; executes live assertions if credentials and resources are active, and executes comprehensive static IaC and contract validations otherwise.
3. **No Facade Tests**: Every test executes genuine evaluation logic against authoritative sources (`ORIGINAL_REQUEST.md`, `PROJECT.md`, survey reports). If a live resource is pending a future milestone, the test explicitly records status as `SKIPPED (Pending Milestone X)` rather than giving a false positive or unhandled crash.

---

## 4. Feature Coverage Matrix (21 Features)

| Feature # | Feature Name | Milestone | Tier 1 Tests | Tier 2 Tests | Tier 3 Integration | Tier 4 Workload |
|---|---|---|---|---|---|---|
| **1** | GitHub Repository Setup | M1 | T1.1.1 – T1.1.5 (5) | T2.1.1 – T2.1.5 (5) | Repo + CI/CD | Dev Workflow |
| **2** | GCP Project Creation & Billing | M1 | T1.2.1 – T1.2.5 (5) | T2.2.1 – T2.2.5 (5) | Billing + APIs | Provisioning |
| **3** | GCP APIs Enablement | M1 | T1.3.1 – T1.3.5 (5) | T2.3.1 – T2.3.5 (5) | APIs + Services | Provisioning |
| **4** | Remote State Storage (GCS) | M1 | T1.4.1 – T1.4.5 (5) | T2.4.1 – T2.4.5 (5) | GCS + Locking | CI/CD Apply |
| **5** | Workload Identity Federation (WIF)| M1 | T1.5.1 – T1.5.5 (5) | T2.5.1 – T2.5.5 (5) | WIF + Actions | PR Lifecycle |
| **6** | Secret Manager Vault | M1 | T1.6.1 – T1.6.5 (5) | T2.6.1 – T2.6.5 (5) | Secrets + Startup | Shell Login |
| **7** | VPC Network & Firewall | M2 | T1.7.1 – T1.7.5 (5) | T2.7.1 – T2.7.5 (5) | VPC + Mosh/IAP | Security Audit |
| **8** | Compute Engine Workstation VM | M2 | T1.8.1 – T1.8.5 (5) | T2.8.1 – T2.8.5 (5) | VM + Disk + SA | Provisioning |
| **9** | 4GB Swapfile & Kernel Tuning | M2 | T1.9.1 – T1.9.5 (5) | T2.9.1 – T2.9.5 (5) | Swap + Sysctl | Dev Build Run |
| **10** | Tailscale & Tailscale SSH | M2 | T1.10.1 – T1.10.5 (5) | T2.10.1 – T2.10.5 (5) | Tailscale + SSH | Shell Login |
| **11** | Mosh & Safe tmux Auto-Attach | M2 | T1.11.1 – T1.11.5 (5) | T2.11.1 – T2.11.5 (5) | Mosh + Tmux | Shell Login |
| **12** | Credential Pre-seeding | M2 | T1.12.1 – T1.12.5 (5) | T2.12.1 – T2.12.5 (5) | SSH + Git Config | Dev Build Run |
| **13** | Developer Toolchain (Node/Python/agy)| M2 | T1.13.1 – T1.13.5 (5) | T2.13.1 – T2.13.5 (5) | Tools + Workspace | Dev Build Run |
| **14** | Project Repository Clone | M2 | T1.14.1 – T1.14.5 (5) | T2.14.1 – T2.14.5 (5) | Git + SSH Remote | Dev Build Run |
| **15** | CI/CD PR Plan Workflow | M3 | T1.15.1 – T1.15.5 (5) | T2.15.1 – T2.15.5 (5) | WIF + Plan + Comment | PR Lifecycle |
| **16** | CI/CD Main Apply Workflow | M3 | T1.16.1 – T1.16.5 (5) | T2.16.1 – T2.16.5 (5) | Apply + State Lock | PR Lifecycle |
| **17** | Portfolio-Grade README | M3 | T1.17.1 – T1.17.5 (5) | T2.17.1 – T2.17.5 (5) | Docs + Diagram | Compliance Audit|
| **18** | Live GCP Turn-up | M4 | T1.18.1 – T1.18.5 (5) | T2.18.1 – T2.18.5 (5) | Bootstrap + Workstation | Provisioning |
| **19** | Programmatic Verification Suite | M4 | T1.19.1 – T1.19.5 (5) | T2.19.1 – T2.19.5 (5) | Verification Script | Provisioning |
| **20** | E2E Testing Suite (Tiers 1-4) | E2E | T1.20.1 – T1.20.5 (5) | T2.20.1 – T2.20.5 (5) | Runner + Suites | Framework Self-Test |
| **21** | Adversarial Hardening (Tier 5) | M5 | T1.21.1 – T1.21.5 (5) | T2.21.1 – T2.21.5 (5) | Security Policies | Security Audit |
| **Total** | **All 21 Features** | — | **105 Tests** | **105 Tests** | **10 Scenarios** | **5 Workloads** |

*Cumulative Grand Total: 225 Automated Test Cases across Tiers 1–4.*

---

## 5. Directory & File Layout

```
~/teamwork_projects/remote_dev_workstation/
├── TEST_INFRA.md                   # Authoritative Test Architecture & Specification (this document)
├── TEST_READY.md                   # Milestone test readiness and execution certification
└── tests/
    ├── e2e_runner.sh               # Main test harness, CLI argument parser, structured reporter
    ├── tier1_feature_tests.sh      # 105 isolated feature test cases (Features 1–21)
    ├── tier2_boundary_tests.sh     # 105 boundary/edge/stress test cases (Features 1–21)
    ├── tier3_integration_tests.sh  # 10 pairwise cross-feature interaction scenarios
    ├── tier4_workload_tests.sh     # 5 end-to-end real-world developer workflows
    └── results/                    # Auto-generated structured logs and JSON reports
        ├── e2e_results_<ts>.log
        └── e2e_results_<ts>.json
```

---

## 6. Test Harness Specification (`tests/e2e_runner.sh`)

### 6.1 CLI Usage & Options

```bash
Usage: ./tests/e2e_runner.sh [OPTIONS]

Options:
  --all                   Execute all test tiers (Tiers 1, 2, 3, 4) [default]
  --tier <1|2|3|4>        Execute only the specified test tier
  --feature <1..21>       Execute tests matching specific Feature ID across active tiers
  --mode <static|live|auto>  Set execution mode (default: auto)
  --stage <M1|M2|M3|M4|M5|all>  Filter tests applicable to milestone stage (default: all)
  --verbose               Enable verbose diagnostic output for every assertion
  --json                  Output test execution summary in machine-readable JSON format
  --dry-run               Enumerate selected tests without executing assertions
  --help, -h              Display this help message
```

### 6.2 Environment Variables

| Variable | Allowed Values | Default | Purpose |
|---|---|---|---|
| `TEST_MODE` | `static`, `live`, `auto` | `auto` | Enforces static validation or live cloud evaluation |
| `STAGE` | `M1`, `M2`, `M3`, `M4`, `M5`, `all` | `all` | Focuses tests on specific implementation milestones |
| `WORKSPACE_ROOT` | Absolute directory path | Repository root | Root directory under test |
| `GCP_PROJECT_ID` | GCP Project ID | auto-detected | Override GCP project for live queries |
| `VERBOSE` | `true`, `false` | `false` | Verbose step logging |

### 6.3 Exit Codes

- `0`: All executed test assertions passed successfully (or skipped due to progressive milestone staging).
- `1`: One or more test assertions failed.
- `2`: Invalid CLI options, missing prerequisites, or initialization error.

---

## 7. Structured Reporting Format

Each test run produces two structured artifacts in `tests/results/`:

1. **Human-Readable Log (`e2e_results_<timestamp>.log`)**: Timestamped execution transcript with colored PASS/FAIL/SKIP indicators and verbatim failure diagnostics.
2. **Machine-Readable JSON (`e2e_results_<timestamp>.json`)**:
   ```json
   {
     "summary": {
       "total": 225,
       "passed": 225,
       "failed": 0,
       "skipped": 0,
       "duration_seconds": 3.42,
       "exit_code": 0
     },
     "environment": {
       "test_mode": "auto",
       "stage": "all",
       "workspace": "/home/zett/teamwork_projects/remote_dev_workstation",
       "timestamp": "2026-11-03T15:00:00Z"
     },
     "results": [
       {
         "id": "T1.1.1",
         "tier": 1,
         "feature_id": 1,
         "name": "Verify GitHub Repository Public Visibility Configuration",
         "status": "PASS",
         "duration_ms": 12,
         "details": "Repository visibility explicitly set to public"
       }
     ]
   }
   ```

---

## 8. Assertion Library Reference

The runner and tier test scripts leverage standard POSIX assertion primitives:

- `assert_eq "$actual" "$expected" "$desc"`: Asserts string equality.
- `assert_ne "$actual" "$expected" "$desc"`: Asserts string inequality.
- `assert_match "$actual" "$regex" "$desc"`: Asserts regex pattern match.
- `assert_contains "$haystack" "$needle" "$desc"`: Asserts substring containment.
- `assert_file_exists "$file" "$desc"`: Asserts filesystem file existence.
- `assert_dir_exists "$dir" "$desc"`: Asserts directory existence.
- `assert_file_contains "$file" "$pattern" "$desc"`: Asserts file contains regex pattern.
- `assert_file_not_contains "$file" "$pattern" "$desc"`: Asserts file excludes pattern.
- `assert_exit_code "$expected_code" "$command" "$desc"`: Executes command and asserts exit code.
- `assert_gt "$actual" "$min" "$desc"`: Asserts integer greater than.

---

## 9. Conclusion

The testing infrastructure guarantees rigorous, deterministic verification of the Mobile Workstation IaC and CI/CD project, maintaining progressive testability from local scaffold to live GCP turn-up.
