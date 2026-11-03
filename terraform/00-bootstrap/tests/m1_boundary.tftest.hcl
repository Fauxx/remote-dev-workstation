# File: terraform/00-bootstrap/tests/m1_boundary.tftest.hcl
# Native Terraform Boundary & Negative Test Suite for Milestone 1

variables {
  org_id         = "705988173122"
  region         = "us-central1"
  github_repo    = "Fauxx/remote-dev-workstation"
  project_prefix = "rdw-workstation"
}

# --------------------------------------------------------------------------
# Negative Boundary Tests: Billing Account Validation
# --------------------------------------------------------------------------
run "reject_invalid_billing_account_format" {
  command = plan

  variables {
    billing_account = "INVALID_BILLING_FORMAT"
  }

  expect_failures = [
    var.billing_account
  ]
}

run "reject_truncated_billing_account" {
  command = plan

  variables {
    billing_account = "01833A-97FE0E"
  }

  expect_failures = [
    var.billing_account
  ]
}

# --------------------------------------------------------------------------
# Negative Boundary Tests: Project Prefix Validation
# --------------------------------------------------------------------------
run "reject_uppercase_project_prefix" {
  command = plan

  variables {
    project_prefix = "RDW-Workstation"
  }

  expect_failures = [
    var.project_prefix
  ]
}

run "reject_underscore_project_prefix" {
  command = plan

  variables {
    project_prefix = "rdw_workstation"
  }

  expect_failures = [
    var.project_prefix
  ]
}

run "reject_trailing_hyphen_prefix" {
  command = plan

  variables {
    project_prefix = "rdw-workstation-"
  }

  expect_failures = [
    var.project_prefix
  ]
}

# --------------------------------------------------------------------------
# Positive Baseline Test: Valid Parameters
# --------------------------------------------------------------------------
run "accept_valid_inputs" {
  command = plan

  variables {
    billing_account = "01833A-97FE0E-12FAE5"
    project_prefix  = "rdw-workstation"
  }

  assert {
    condition     = var.region == "us-central1"
    error_message = "Default region must be us-central1"
  }

  assert {
    condition     = var.github_repo == "Fauxx/remote-dev-workstation"
    error_message = "GitHub repository target must be Fauxx/remote-dev-workstation"
  }

  assert {
    condition     = var.project_prefix == "rdw-workstation"
    error_message = "Project prefix must be rdw-workstation"
  }
}
