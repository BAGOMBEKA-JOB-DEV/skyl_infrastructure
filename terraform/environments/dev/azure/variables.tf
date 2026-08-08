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
  description = "Image digest to deploy. Printed by skyl's publish-image workflow."
  type        = string
}

variable "gateway_hosts" {
  description = "Hostnames to serve. Empty leaves the gateway in-cluster only."
  type        = list(string)
  default     = []
}

variable "authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API. Open by default in dev; narrow it if you can."
  type        = list(string)
  default     = []
}

variable "key_vault_allowed_ips" {
  description = "Public IPs allowed to reach Key Vault directly. AKS and Terraform already get in via the AzureServices bypass."
  type        = list(string)
  default     = []
}

variable "admin_group_object_ids" {
  description = <<-EOT
    Entra ID groups granted cluster-admin. With local_account_disabled=true on
    the cluster, leaving this empty means nobody can reach the API until an
    Azure RBAC role is assigned by hand.
  EOT
  type        = list(string)
  default     = []
}
