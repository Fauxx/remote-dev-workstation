output "instance_name" {
  description = "The name of the Compute Engine developer workstation VM instance"
  value       = google_compute_instance.workstation.name
}

output "instance_zone" {
  description = "The Google Cloud zone hosting the workstation instance"
  value       = google_compute_instance.workstation.zone
}

output "instance_internal_ip" {
  description = "The private RFC 1918 internal IPv4 address of the workstation within the VPC subnetwork"
  value       = google_compute_instance.workstation.network_interface[0].network_ip
}

output "instance_external_ip" {
  description = "The public external IPv4 address allocated to the workstation instance"
  value       = try(google_compute_instance.workstation.network_interface[0].access_config[0].nat_ip, "")
}

output "vpc_network_name" {
  description = "The name of the custom VPC network hosting the workstation"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "The name of the custom subnetwork hosting the workstation"
  value       = google_compute_subnetwork.subnet.name
}

# ------------------------------------------------------------------------------
# CONVENIENCE CONNECTION HELPERS
# ------------------------------------------------------------------------------

output "iap_ssh_command" {
  description = "Command to connect to the workstation securely via Google Cloud IAP"
  value       = "gcloud compute ssh ${google_compute_instance.workstation.name} --zone=${google_compute_instance.workstation.zone} --tunnel-through-iap"
}

output "tailscale_ssh_command" {
  description = "Command to connect to the workstation via Tailscale SSH"
  value       = "ssh ubuntu@${google_compute_instance.workstation.name}"
}

output "mosh_command" {
  description = "Command to connect to the workstation via Mobile Shell (Mosh)"
  value       = "mosh ubuntu@${try(google_compute_instance.workstation.network_interface[0].access_config[0].nat_ip, "")}"
}
