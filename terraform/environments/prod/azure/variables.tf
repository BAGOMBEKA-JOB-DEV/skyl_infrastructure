variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "region" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "gateway_image_digest" {
  description = "Image digest to deploy. From skyl's publish-image workflow summary."
  type        = string
}

variable "gateway_hosts" {
  description = "Hostnames to serve. Required in prod."
  type        = list(string)

  validation {
    condition     = length(var.gateway_hosts) > 0
    error_message = "gateway_hosts must not be empty in prod; cert-manager also needs a host to issue for."
  }
}

variable "authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API. Required in prod."
  type        = list(string)

  validation {
    condition     = length(var.authorized_networks) > 0
    error_message = "authorized_networks must be set in prod."
  }
}

variable "admin_group_object_ids" {
  description = <<-EOT
    Entra ID groups granted cluster-admin.

    Required in prod. The module sets local_account_disabled = true, so with an
    empty list nobody can reach the API at all until an Azure RBAC role is
    assigned by hand — a bad thing to discover during an incident.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.admin_group_object_ids) > 0
    error_message = "admin_group_object_ids must be set in prod, or nobody can reach the cluster (local accounts are disabled)."
  }
}

variable "key_vault_allowed_ips" {
  description = "Public IPs allowed to reach Key Vault directly. Usually empty: AKS and Terraform enter via the AzureServices bypass."
  type        = list(string)
  default     = []
}
