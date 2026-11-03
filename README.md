# Production IaC & CI/CD Mobile Workstation

An automated, enterprise-grade cloud developer workstation deployed on Google Cloud Platform (GCP) with layered Terraform Infrastructure as Code (IaC) and GitHub Actions CI/CD authenticated via Google Cloud Workload Identity Federation (WIF).

## Architecture Overview

```
   [ Developer Client (Laptop / Mobile / Tablet) ]
                         │
      Tailscale Mesh (WireGuard encrypted) / Mosh
                         │
                         ▼
        ┌──────────────────────────────────┐
        │       GCP VPC (us-central1)      │
        │                                  │
        │  [ Compute Engine: e2-medium ]   │
        │  - Ubuntu 24.04 LTS (50GB disk)  │
        │  - 4GB Swapfile & Swappiness     │
        │  - Tailscale with Tailscale SSH  │
        │  - Mosh (UDP 60000-61000)        │
        │  - tmux safe auto-attach         │
        │  - Node.js 22 LTS & Python 3     │
        │  - agy CLI (Antigravity v1.4.12) │
        │  - Cloned FireMonitoringSystem   │
        └──────────────────────────────────┘
                         ▲
                         │ Instance Metadata / Secret Accessor
        ┌──────────────────────────────────┐
        │      Google Cloud Platform       │
        │  - Secret Manager (Keys, Tokens) │
        │  - Cloud Storage (Remote State)  │
        │  - Workload Identity Pool/OIDC   │
        └──────────────────────────────────┘
                         ▲
                         │ Keyless OIDC (google-github-actions/auth@v2)
        ┌──────────────────────────────────┐
        │  GitHub Actions CI/CD Workflows  │
        │  - PR: terraform plan            │
        │  - Main Push: terraform apply    │
        │  - Repo: remote-dev-workstation  │
        └──────────────────────────────────┘
```

## Repository Structure

```
remote-dev-workstation/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml       # PR validation with WIF auth
│       └── terraform-apply.yml      # Main push deployment with WIF auth
├── terraform/
│   ├── 00-bootstrap/
│   │   ├── main.tf                  # Project, APIs, State Bucket, WIF, SAs, Secrets
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   ├── terraform.tfvars.example
│   │   └── tests/
│   │       └── m1_boundary.tftest.hcl
│   └── 01-workstation/
│       ├── main.tf                  # VPC, Subnet, Firewall, Compute Instance
│       ├── startup.sh               # Hardened VM bootstrap script
│       ├── variables.tf
│       └── outputs.tf
├── scripts/
│   ├── bootstrap-local.sh          # 3-phase local-to-remote state migration helper
│   ├── verify_m1_contract.sh       # M1 Quality & Contract verification audit
│   └── verify-workstation.sh       # Programmatic health and tooling check
├── docs/
│   ├── architecture.md
│   └── security-model.md
└── tests/                           # E2E Test Suite
```

## Security & Architecture Principles

1. **Zero Static Credentials**: Authentication in GitHub Actions relies 100% on Workload Identity Federation (WIF) and short-lived Google STS tokens. No static JSON service account keys are created or stored.
2. **Zero-Trust Networking**: Workstation access is mediated through Tailscale WireGuard mesh networking and Tailscale SSH with keyless node authorization. Direct external SSH is locked down.
3. **Secret Isolation**: Secret Manager shells are declared in Terraform; sensitive secret versions and payloads are injected out-of-band and retrieved at runtime via IAM-authorized instance metadata calls.
4. **Non-Authoritative IAM**: IAM role grants use additive `google_project_iam_member` resources to prevent revoking administrator permissions.
