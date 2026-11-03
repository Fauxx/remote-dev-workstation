# ==============================================================================
# 1. RANDOM IDENTIFIERS FOR COLLISION PREVENTION
# ==============================================================================

# Generates 4 hex characters (2 bytes) for unique project naming (e.g., rdw-workstation-8a2f)
# Length: 15 (prefix) + 1 (hyphen) + 4 (hex) = 20 chars (GCP limit: 6-30 chars)
resource "random_id" "project_suffix" {
  byte_length = 2
}

# Generates 8 hex characters (4 bytes) for globally unique GCS state bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==============================================================================
# 2. GOOGLE CLOUD PROJECT PROVISIONING
# ==============================================================================

resource "google_project" "workstation" {
  name                = "${var.project_prefix}-${random_id.project_suffix.hex}"
  project_id          = "${var.project_prefix}-${random_id.project_suffix.hex}"
  org_id              = var.org_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "DELETE"
}

# ==============================================================================
# 3. GOOGLE CLOUD API ACTIVATION
# ==============================================================================

locals {
  required_services = toset([
    "cloudresourcemanager.googleapis.com", # Project resource metadata and project-level IAM
    "serviceusage.googleapis.com",         # Programmatic API enablement
    "compute.googleapis.com",              # Compute instances, VPC networking, firewall rules
    "iam.googleapis.com",                  # Service accounts, Workload Identity Pools
    "iamcredentials.googleapis.com",       # STS token minting for WIF
    "sts.googleapis.com",                  # Security Token Service for GitHub OIDC
    "secretmanager.googleapis.com",        # Secret Manager vault for keys and tokens
    "storage.googleapis.com",              # Cloud Storage for remote state
    "logging.googleapis.com",              # Cloud Logging for host logs
    "monitoring.googleapis.com",           # Cloud Monitoring for VM metrics
  ])
}

resource "google_project_service" "apis" {
  for_each = local.required_services
  project  = google_project.workstation.project_id
  service  = each.key

  # Prevent accidental disabling of core APIs during state refresh or resource destruction
  disable_on_destroy         = false
  disable_dependent_services = false

  depends_on = [
    google_project.workstation
  ]
}

# ==============================================================================
# 4. REMOTE TERRAFORM STATE STORAGE (GCS)
# ==============================================================================

resource "google_storage_bucket" "state" {
  name                        = "${var.state_bucket_prefix}-${random_id.bucket_suffix.hex}"
  project                     = google_project.workstation.project_id
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Protect state bucket from accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [
    google_project_service.apis
  ]
}

# ==============================================================================
# 5. WORKLOAD IDENTITY FEDERATION (WIF) FOR GITHUB ACTIONS CI/CD
# ==============================================================================

resource "google_iam_workload_identity_pool" "github_pool" {
  project                   = google_project.workstation.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions CI/CD workflows"

  depends_on = [
    google_project_service.apis
  ]
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  project                            = google_project.workstation.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC Provider"
  description                        = "OIDC Provider for GitHub Actions token exchange"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Strictly restrict token exchange to assertions coming from the designated repository
  attribute_condition = "assertion.repository == '${var.github_repo}'"
}

# ==============================================================================
# 6. SERVICE ACCOUNTS
# ==============================================================================

# CI/CD Automation Service Account used by GitHub Actions
resource "google_service_account" "ci_cd" {
  project      = google_project.workstation.project_id
  account_id   = "sa-github-actions"
  display_name = "CI/CD GitHub Actions Service Account"
  description  = "Service Account impersonated by GitHub Actions via Workload Identity Federation"

  depends_on = [
    google_project_service.apis
  ]
}

# Workstation VM Runtime Identity
resource "google_service_account" "workstation_vm" {
  project      = google_project.workstation.project_id
  account_id   = "sa-workstation-vm"
  display_name = "Workstation VM Service Account"
  description  = "Runtime identity for Compute Engine developer workstation VM"

  depends_on = [
    google_project_service.apis
  ]
}

# ==============================================================================
# 7. WORKLOAD IDENTITY FEDERATION SERVICE ACCOUNT IMPERSONATION BINDING
# ==============================================================================

resource "google_service_account_iam_member" "ci_cd_wif" {
  service_account_id = google_service_account.ci_cd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# ==============================================================================
# 8. NON-AUTHORITATIVE PROJECT IAM ROLE BINDINGS
# ==============================================================================

locals {
  # Scoped permissions enabling CI/CD to provision and manage 01-workstation resources
  ci_cd_roles = [
    "roles/compute.admin",                   # VPC networks, subnets, firewall rules, disks, VM instances
    "roles/iam.serviceAccountUser",          # Attach sa-workstation-vm to Compute Engine VM
    "roles/storage.objectAdmin",             # Read and write remote state objects in GCS bucket
    "roles/secretmanager.admin",             # Manage Secret Manager secrets and versions
    "roles/resourcemanager.projectIamAdmin", # Manage project-level IAM bindings
  ]

  # Strict least-privilege telemetry roles for workstation VM runtime
  vm_roles = [
    "roles/logging.logWriter",       # Push system, auth, and application logs to Cloud Logging
    "roles/monitoring.metricWriter", # Ship host performance metrics to Cloud Monitoring
  ]
}

# Additive IAM binding for CI/CD SA — prevents wiping existing project owners/admins
resource "google_project_iam_member" "ci_cd" {
  for_each = toset(local.ci_cd_roles)
  project  = google_project.workstation.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.ci_cd.email}"
}

# Additive IAM binding for Workstation VM SA
resource "google_project_iam_member" "workstation_vm" {
  for_each = toset(local.vm_roles)
  project  = google_project.workstation.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.workstation_vm.email}"
}

# ==============================================================================
# 9. SECRET MANAGER VAULT AND ACCESSOR IAM
# ==============================================================================

locals {
  secret_names = toset([
    "tailscale-auth-key",     # Reusable pre-authenticated key for headless Tailscale registration
    "github-ssh-private-key", # SSH private key for GitHub repo access and commits
    "github-pat-token",       # GitHub Personal Access Token for GitHub CLI authentication
  ])
}

# Provision secret containers/shells (zero version payloads hardcoded in Terraform)
resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secret_names
  project   = google_project.workstation.project_id
  secret_id = each.key

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.apis
  ]
}

# Grant secret-level accessor permission to Workstation VM SA (resource-level least privilege)
resource "google_secret_manager_secret_iam_member" "vm_secret_accessor" {
  for_each  = google_secret_manager_secret.secrets
  project   = google_project.workstation.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workstation_vm.email}"
}
