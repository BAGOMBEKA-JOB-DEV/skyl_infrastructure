# The contract. See ../CONTRACT.md — identical names and types across all three
# cloud modules.

output "cluster_name" {
  description = "Cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "Running control-plane version."
  value       = module.eks.cluster_version
}

output "oidc_issuer_url" {
  description = "IRSA OIDC issuer."
  value       = module.eks.cluster_oidc_issuer_url
}

output "workload_identity_annotation" {
  description = "Annotation for External Secrets' ServiceAccount. The key is AWS-specific; consumers pass it through without reading it."
  value = {
    "eks.amazonaws.com/role-arn" = module.external_secrets_irsa.iam_role_arn
  }
}

output "secret_store_backend" {
  description = "External Secrets provider to configure."
  value       = "aws"
}

output "secret_store_config" {
  description = "Provider-specific settings for the ClusterSecretStore."
  value = {
    region  = var.region
    service = "SecretsManager"
  }
}

output "ingress_class" {
  description = "ingress-nginx, for identical behaviour across clouds. See docs/adr/0002."
  value       = "nginx"
}

output "node_architecture" {
  description = "Graviton nodes; the gateway image is multi-arch."
  value       = "arm64"
}

output "region" {
  description = "Region the cluster runs in."
  value       = var.region
}

# --- beyond the contract -----------------------------------------------------

output "external_secrets_role_arn" {
  description = "IAM role External Secrets assumes."
  value       = module.external_secrets_irsa.iam_role_arn
}

output "vpc_id" {
  description = "VPC the cluster runs in."
  value       = module.vpc.vpc_id
}
