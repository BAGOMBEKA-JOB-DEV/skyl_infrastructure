# The contract. See ../CONTRACT.md — these names and types are identical across
# aws/, gcp/ and azure/, and everything above consumes only these.

output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = "https://${google_container_cluster.this.endpoint}"
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_version" {
  description = "Running control-plane version."
  value       = google_container_cluster.this.master_version
}

output "oidc_issuer_url" {
  description = "Workload Identity pool, GCP's equivalent of an OIDC issuer."
  value       = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/clusters/${google_container_cluster.this.name}"
}

output "workload_identity_annotation" {
  description = "Annotation for External Secrets' ServiceAccount. The key is GCP-specific; consumers pass it through without reading it."
  value = {
    "iam.gke.io/gcp-service-account" = google_service_account.external_secrets.email
  }
}

output "secret_store_backend" {
  description = "External Secrets provider to configure."
  value       = "gcpsm"
}

output "secret_store_config" {
  description = "Provider-specific settings for the ClusterSecretStore."
  value = {
    projectID = var.project_id
  }
}

output "ingress_class" {
  description = "ingress-nginx, for identical behaviour across clouds. See docs/adr/0002."
  value       = "nginx"
}

output "node_architecture" {
  description = "Autopilot schedules amd64 unless a pod requests otherwise."
  value       = "amd64"
}

output "region" {
  description = "Region the cluster runs in."
  value       = var.region
}

# --- beyond the contract -----------------------------------------------------
# Extra outputs are allowed; the contract is a minimum, not a maximum. Nothing
# shared may depend on these.

output "external_secrets_service_account_email" {
  description = "GCP service account External Secrets impersonates."
  value       = google_service_account.external_secrets.email
}

output "network_name" {
  description = "VPC name."
  value       = google_compute_network.this.name
}
