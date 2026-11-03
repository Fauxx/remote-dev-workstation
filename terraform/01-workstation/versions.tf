terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    prefix = "terraform/state/01-workstation"
  }
}

provider "google" {
  project = local.project_id
  region  = var.region
  zone    = var.zone
}
