variable "name" {
  description = "Cluster name prefix. Combined with environment."
  type        = string
  default     = "skyl"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "region" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "cluster_version" {
  description = "AKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "sku_tier" {
  description = <<-EOT
    Free has no uptime SLA and no cost. Standard is ~$73/month and is what you
    want for anything anyone depends on.
  EOT
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "vm_size" {
  description = "Node VM size. Standard_D2ps_v5 is Ampere/arm64 and cheaper; the gateway image is multi-arch."
  type        = string
  default     = "Standard_D2ps_v5"
}

variable "node_count" {
  description = "Node count."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "node_count must be at least 2; a single node cannot satisfy the PodDisruptionBudget during an upgrade."
  }
}

variable "vnet_cidr" {
  description = "Virtual network address space."
  type        = string
  default     = "10.50.0.0/16"
}

variable "node_subnet_cidr" {
  description = "Node subnet. Overlay mode means pods do not consume VNet addresses, so this can be small."
  type        = string
  default     = "10.50.0.0/20"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VNet."
  type        = string
  default     = "10.60.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS address. Must be inside service_cidr."
  type        = string
  default     = "10.60.0.10"

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0))
    error_message = "dns_service_ip must be a valid IP address."
  }
}

variable "admin_group_object_ids" {
  description = <<-EOT
    Entra ID group object IDs granted cluster-admin. Empty is allowed, but with
    local_account_disabled=true it means nobody can reach the cluster until an
    Azure RBAC role is assigned out of band.
  EOT
  type        = list(string)
  default     = []
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API. Empty leaves it open, which is
    the provider default and is not what you want in prod — the API is still
    authenticated, but it should not be reachable from everywhere.

    Mirrors the same input on the AWS and GCP modules; the three differ only in
    how the provider spells it.
  EOT
  type        = list(string)
  default     = []
}

variable "key_vault_allowed_ips" {
  description = <<-EOT
    Public IPs allowed to reach Key Vault directly, on top of the
    `bypass = AzureServices` rule that lets AKS and Terraform in. Usually empty:
    the gateway reads secrets through External Secrets, not over the internet.

    Set this only if you need `az keyvault secret set` to work from a laptop
    outside a trusted network.
  EOT
  type        = list(string)
  default     = []
}

variable "external_secrets_namespace" {
  description = "Namespace External Secrets Operator runs in."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_sa_name" {
  description = "External Secrets' Kubernetes ServiceAccount name."
  type        = string
  default     = "external-secrets"
}

variable "secret_names" {
  description = "Key Vault secrets to create as placeholders. Real values are set out of band; a secret in Terraform is a secret in state."
  type        = list(string)
  default = [
    "skyl-gateway-auth-token",
    "skyl-anthropic-api-key",
  ]
}

variable "tags" {
  description = "Tags applied to every resource that accepts them."
  type        = map(string)
  default     = {}
}
