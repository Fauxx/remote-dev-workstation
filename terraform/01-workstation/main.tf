# ==============================================================================
# Remote Dev Workstation: Main Infrastructure Specification
# Ingests remote state from 00-bootstrap via data "terraform_remote_state" "bootstrap"
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. NETWORKING: ISOLATED CUSTOM VPC & SUBNETWORK
# ------------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = "rdw-workstation-vpc"
  auto_create_subnetworks = false
  description             = "Custom isolated VPC network for remote developer workstation"
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "rdw-workstation-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Private subnet with Google API access enabled for workstation"
}

# ------------------------------------------------------------------------------
# 2. ZERO-TRUST FIREWALL RULES
# ------------------------------------------------------------------------------

# Allow WireGuard UDP traffic on port 41641 for Tailscale Mesh direct connections
resource "google_compute_firewall" "allow_tailscale" {
  name        = "allow-tailscale"
  network     = google_compute_network.vpc.name
  description = "Allow inbound WireGuard traffic on UDP port 41641 for Tailscale direct connections"

  allow {
    protocol = "udp"
    ports    = ["41641"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tailscale"]
}

# Allow Mobile Shell (Mosh) UDP packet roaming on ports 60000-61000
resource "google_compute_firewall" "allow_mosh" {
  name        = "allow-mosh"
  network     = google_compute_network.vpc.name
  description = "Allow inbound UDP packets on ports 60000-61000 for Mobile Shell (Mosh) roaming sessions"

  allow {
    protocol = "udp"
    ports    = ["60000-61000"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mosh"]
}

# Allow emergency / break-glass SSH exclusively from Google Cloud IAP CIDR range
# Direct public 0.0.0.0/0 on port 22 is STRICTLY PROHIBITED.
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "allow-iap-ssh"
  network     = google_compute_network.vpc.name
  description = "Allow SSH ingress strictly from Google Cloud Identity-Aware Proxy (IAP) CIDR range"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["workstation"]
}

# Allow internal subnet traffic (ICMP, TCP, UDP) for local diagnostics
resource "google_compute_firewall" "allow_internal" {
  name        = "allow-internal"
  network     = google_compute_network.vpc.name
  description = "Allow ICMP and internal communication within the workstation subnet"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [google_compute_subnetwork.subnet.ip_cidr_range]
}

# ------------------------------------------------------------------------------
# 3. COMPUTE ENGINE INSTANCE: DEVELOPER WORKSTATION
# ------------------------------------------------------------------------------

resource "google_compute_instance" "workstation" {
  name         = var.instance_name
  machine_type = var.machine_type # default: e2-medium
  zone         = var.zone
  description  = "Mobile developer workstation VM running Ubuntu 24.04 LTS"

  tags = ["workstation", "tailscale", "mosh"]

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = var.boot_disk_size_gb # size = 50
      type  = var.boot_disk_type    # pd-balanced
      labels = {
        managed-by = "terraform"
        role       = "workstation"
        os         = "ubuntu-2404-lts"
      }
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {
      # Ephemeral external IPv4 address assigned for outbound software downloads
    }
  }

  # Dedicated runtime service account with least-privilege telemetry and secret access
  service_account {
    email  = local.workstation_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = file("${path.module}/startup.sh")
  }

  # On-demand instance persistence (preemptible / spot prohibited for persistent developer host)
  scheduling {
    preemptible         = false
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"]
    ]
  }

  depends_on = [
    google_compute_firewall.allow_iap_ssh,
    google_compute_firewall.allow_tailscale,
    google_compute_firewall.allow_mosh
  ]
}
