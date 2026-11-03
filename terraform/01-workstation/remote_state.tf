# ==============================================================================
# REMOTE STATE INGESTION FROM 00-BOOTSTRAP
# ==============================================================================

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"

  config = {
    bucket = var.remote_state_bucket
    prefix = "terraform/state/00-bootstrap"
  }
}

locals {
  # Project ID resolution: Explicit variable override takes precedence over bootstrap state
  project_id = coalesce(
    var.project_id,
    try(data.terraform_remote_state.bootstrap.outputs.project_id, null)
  )

  # Runtime service account attached to workstation VM
  workstation_sa_email = try(
    data.terraform_remote_state.bootstrap.outputs.workstation_service_account_email,
    null
  )
}
