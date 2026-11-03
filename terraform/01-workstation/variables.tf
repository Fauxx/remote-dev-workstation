variable "project_id" {
  description = "The Google Cloud Project ID. If empty or null, defaults to project_id from 00-bootstrap remote state."
  type        = string
  default     = null
}

variable "region" {
  description = "Default Google Cloud region for regional networking and compute resources"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+$", var.region))
    error_message = "The region must be a valid GCP region format (e.g. 'us-central1')."
  }
}

variable "zone" {
  description = "Compute Engine zone for the workstation instance"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "The zone must be a valid GCP zonal format (e.g. 'us-central1-a')."
  }
}

variable "machine_type" {
  description = "Compute Engine machine type for the workstation VM"
  type        = string
  default     = "e2-medium"

  validation {
    condition     = contains(["e2-medium", "e2-standard-2", "e2-standard-4"], var.machine_type)
    error_message = "The machine_type must be a supported general-purpose type (default: 'e2-medium')."
  }
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in gigabytes (minimum 50GB required for developer toolchain, swapfile, and repo builds)"
  type        = number
  default     = 50

  validation {
    condition     = var.boot_disk_size_gb >= 50
    error_message = "Boot disk size must be at least 50 GB to prevent disk exhaustion."
  }
}

variable "boot_disk_type" {
  description = "Persistent disk type for instance boot disk"
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "The boot_disk_type must be one of: 'pd-standard', 'pd-balanced', 'pd-ssd'."
  }
}

variable "remote_state_bucket" {
  description = "Name of the GCS bucket storing the 00-bootstrap Terraform remote state"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Host name for the Compute Engine developer workstation"
  type        = string
  default     = "mobile-workstation"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.instance_name))
    error_message = "The instance_name must comply with RFC 1035 naming rules (lowercase letters, numbers, and hyphens)."
  }
}

variable "subnet_cidr" {
  description = "RFC 1918 CIDR block for the custom workstation subnetwork"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "The subnet_cidr must be a valid IPv4 CIDR block."
  }
}
