output "project_id" {
  description = "The Google Cloud Project ID of the provisioned workstation project"
  value       = google_project.workstation.project_id
}

output "project_number" {
  description = "The numeric Google Cloud Project Number"
  value       = google_project.workstation.number
}

output "workstation_service_account_email" {
  description = "The email address of the Workstation VM runtime service account"
  value       = google_service_account.workstation_vm.email
}

output "ci_service_account_email" {
  description = "The email address of the CI/CD GitHub Actions service account"
  value       = google_service_account.ci_cd.email
}

output "wif_pool_name" {
  description = "The resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_pool.name
}

output "wif_provider_name" {
  description = "The full provider resource identifier for GitHub Actions Workload Identity Federation"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}

output "state_bucket_name" {
  description = "The globally unique name of the GCS bucket for remote Terraform state storage"
  value       = google_storage_bucket.state.name
}

output "secret_manager_ids" {
  description = "Map of created Secret Manager secret IDs to their fully qualified resource identifiers"
  value = {
    for k, v in google_secret_manager_secret.secrets : k => v.id
  }
}
