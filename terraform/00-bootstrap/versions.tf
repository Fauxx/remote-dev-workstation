terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # NOTE: During initial bootstrapping (Phase 1), keep the backend block commented out
  # so that state is written locally. Once 00-bootstrap is applied and the GCS bucket
  # is created, backend.tf is generated dynamically or this block can be uncommented:
  #
  # backend "gcs" {
  #   prefix = "terraform/state/00-bootstrap"
  # }
}

provider "google" {
  # Default authentication is provided via ADC (Application Default Credentials)
  # or Workload Identity Federation in CI/CD.
}
