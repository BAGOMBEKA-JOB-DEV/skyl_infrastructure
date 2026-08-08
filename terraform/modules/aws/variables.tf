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
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR. /16 leaves room for the subnet split below."
  type        = string
  default     = "10.40.0.0/16"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "instance_types" {
  description = <<-EOT
    Node instance types. Graviton (7g family) — the gateway image is multi-arch
    so arm64 costs ~20% less for the same throughput on an I/O-bound service.
  EOT
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "node_count" {
  description = "Desired node count. Max is three times this."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "node_count must be at least 2; a single node cannot satisfy the PodDisruptionBudget during a node upgrade."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    One NAT gateway for all AZs. Saves ~$32/month per AZ avoided; the cost is
    degraded egress during a zonal outage. Defaults to true in dev, and should
    be false in prod.
  EOT
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API. Defaults to open, which is the
    module default and is wrong for prod — narrow it to your office and CI
    ranges.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
  description = "Secrets Manager containers to create. Values are set out of band; a secret in Terraform is a secret in state."
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
