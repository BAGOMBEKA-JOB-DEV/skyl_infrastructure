# The contract. See ../CONTRACT.md — identical names and types across all three
# cloud modules.

output "cluster_name" {
  description = "Cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = "https://${azurerm_kubernetes_cluster.this.fqdn}"
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = azurerm_kubernetes_cluster.this.kube_config[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_version" {
  description = "Running control-plane version."
  value       = azurerm_kubernetes_cluster.this.kubernetes_version
}

output "oidc_issuer_url" {
  description = "Workload identity OIDC issuer."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "workload_identity_annotation" {
  description = "Annotation for External Secrets' ServiceAccount. The key is Azure-specific; consumers pass it through without reading it."
  value = {
    "azure.workload.identity/client-id" = azurerm_user_assigned_identity.external_secrets.client_id
  }
}

output "secret_store_backend" {
  description = "External Secrets provider to configure."
  value       = "azurekv"
}

output "secret_store_config" {
  description = "Provider-specific settings for the ClusterSecretStore."
  value = {
    vaultUrl = azurerm_key_vault.this.vault_uri
    tenantId = data.azurerm_client_config.current.tenant_id
  }
}

output "ingress_class" {
  description = "ingress-nginx, for identical behaviour across clouds. See docs/adr/0002."
  value       = "nginx"
}

output "node_architecture" {
  description = "Ampere nodes by default; the gateway image is multi-arch."
  value       = "arm64"
}

output "region" {
  description = "Region the cluster runs in."
  value       = var.region
}

# --- beyond the contract -----------------------------------------------------

output "resource_group_name" {
  description = "Resource group holding every resource in this module."
  value       = azurerm_resource_group.this.name
}

output "key_vault_name" {
  description = "Key Vault holding the gateway's secrets."
  value       = azurerm_key_vault.this.name
}
