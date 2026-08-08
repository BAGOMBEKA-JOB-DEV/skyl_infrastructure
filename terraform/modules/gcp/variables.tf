variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name" {
  description = "Cluster name prefix. Combined with environment."
  type        = string
  default     = "skyl"

  validation {
    # GKE names are RFC-1035 labels, and the failure arrives at apply time
    # after the network has already been created.
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
  description = "GCP region. Regional clusters spread the control plane across zones."
  type        = string
  default     = "europe-west1"
}

variable "subnet_cidr" {
  description = "Primary node subnet."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pod_cidr" {
  description = "Secondary range for pods. Autopilot allocates generously; /16 avoids exhaustion."
  type        = string
  default     = "10.20.0.0/16"
}

variable "service_cidr" {
  description = "Secondary range for services."
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_cidr" {
  description = "Control-plane range. Must not overlap any other range, and cannot be changed after creation."
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API. Empty means open to the internet,
    which is the provider default and is not what you want in prod — the API is
    still authenticated, but it should not be reachable from everywhere.
  EOT
  type = list(object({
    cidr = string
    name = string
  }))
  default = []
}

variable "release_channel" {
  description = "GKE release channel. REGULAR balances currency against churn."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
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
  description = <<-EOT
    Secret Manager containers to create. Values are NOT set here — a secret in
    Terraform is a secret in state. Populate with `gcloud secrets versions add`.
  EOT
  type        = list(string)
  default = [
    "skyl-gateway-auth-token",
    "skyl-anthropic-api-key",
  ]
}

# Genuinely unused, and deliberately so. CONTRACT.md requires every cloud
# module to accept `node_count` so the environments can be written once, but
# Autopilot has no node pools to size — GKE schedules and bills per pod. The
# variable exists to satisfy the interface.
#
# Removing it would break the contract; consuming it would mean inventing a
# node pool Autopilot does not have.
#
# The directive below must stay on the line immediately preceding the block;
# tflint does not scan back through an intervening comment block.
# tflint-ignore: terraform_unused_declarations
variable "node_count" {
  description = "Accepted for contract compatibility. Autopilot has no node pools; it is ignored."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Labels applied to every resource that accepts them."
  type        = map(string)
  default     = {}
}
