variable "org_id" {
  description = "Google Cloud Organization ID where the project will be created"
  type        = string
  default     = "705988173122"

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "The org_id must be a numeric string containing only digits."
  }
}

variable "billing_account" {
  description = "Google Cloud Billing Account ID to associate with the project"
  type        = string
  default     = "01833A-97FE0E-12FAE5"

  validation {
    condition     = can(regex("^[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}$", var.billing_account))
    error_message = "The billing_account must be in the format 'XXXXXX-XXXXXX-XXXXXX' with hexadecimal characters."
  }
}

variable "region" {
  description = "Default Google Cloud region for regional resources (e.g. GCS state bucket)"
  type        = string
  default     = "us-central1"
}

variable "project_prefix" {
  description = "Prefix prepended to the generated GCP project ID and display name"
  type        = string
  default     = "rdw-workstation"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.project_prefix))
    error_message = "The project_prefix must start with a lowercase letter, contain only lowercase letters, digits, or hyphens, cannot end with a hyphen, and be between 3 and 20 characters."
  }
}

variable "state_bucket_prefix" {
  description = "Prefix prepended to the globally unique GCS Terraform state bucket name"
  type        = string
  default     = "rdw-tfstate"
}

variable "github_repo" {
  description = "GitHub repository in 'owner/repo' format permitted to authenticate via Workload Identity Federation"
  type        = string
  default     = "Fauxx/remote-dev-workstation"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "The github_repo must be formatted as 'owner/repo' with valid GitHub repository name characters."
  }
}
