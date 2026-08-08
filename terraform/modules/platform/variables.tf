# Inputs are the cloud module's contract outputs, plus deployment choices.
# Nothing here names a cloud; see ../CONTRACT.md.

# --- from the cloud module ---------------------------------------------------

variable "cluster_name" {
  description = "Contract output: cluster name."
  type        = string
}

variable "region" {
  description = "Contract output: region."
  type        = string
}

variable "workload_identity_annotation" {
  description = "Contract output: annotation for External Secrets' ServiceAccount. Passed through verbatim; the key is provider-specific."
  type        = map(string)
}

variable "secret_store_backend" {
  description = "Contract output: which External Secrets provider to configure."
  type        = string

  validation {
    condition     = contains(["aws", "gcpsm", "azurekv"], var.secret_store_backend)
    error_message = "secret_store_backend must be aws, gcpsm or azurekv."
  }
}

variable "secret_store_config" {
  description = "Contract output: provider-specific settings for the ClusterSecretStore."
  type        = map(string)
}

variable "ingress_class" {
  description = "Contract output: ingress class."
  type        = string
  default     = "nginx"
}

variable "node_architecture" {
  description = "Contract output: node CPU architecture, used as a scheduling hint."
  type        = string
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.node_architecture)
    error_message = "node_architecture must be amd64 or arm64."
  }
}

# --- deployment --------------------------------------------------------------

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "gateway_image_digest" {
  description = <<-EOT
    Image digest, e.g. sha256:abc... Printed by skyl's publish-image workflow.
    A digest rather than a tag so the deployment is reproducible and matches
    what cosign signed.
  EOT
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.gateway_image_digest))
    error_message = "gateway_image_digest must be a full sha256: digest, not a tag."
  }
}

variable "gateway_hosts" {
  description = "Hostnames to serve. Empty disables the Ingress and leaves the gateway reachable only in-cluster."
  type        = list(string)
  default     = []
}

variable "gateway_values" {
  description = "Extra Helm values, merged over the defaults computed here. Escape hatch; prefer a named variable."
  type        = any
  default     = {}
}

variable "gateway_namespace" {
  description = "Namespace for the gateway."
  type        = string
  default     = "skyl"
}

# --- add-ons -----------------------------------------------------------------

variable "external_secrets_namespace" {
  description = "Namespace for External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_sa_name" {
  description = "External Secrets' ServiceAccount name. Must match what the cloud module bound its identity to."
  type        = string
  default     = "external-secrets"
}

variable "secret_store_name" {
  description = "ClusterSecretStore name the gateway's ExternalSecret references."
  type        = string
  default     = "skyl-secret-store"
}

variable "ingress_namespace" {
  description = "Namespace for ingress-nginx and cert-manager."
  type        = string
  default     = "ingress-nginx"
}

variable "monitoring_namespace" {
  description = "Namespace for the Prometheus stack."
  type        = string
  default     = "monitoring"
}

variable "monitoring_enabled" {
  description = "Install kube-prometheus-stack, and enable the gateway's ServiceMonitor and PrometheusRule."
  type        = bool
  default     = true
}

variable "grafana_enabled" {
  description = "Install Grafana alongside Prometheus."
  type        = bool
  default     = true
}

variable "cert_manager_enabled" {
  description = "Install cert-manager and annotate the Ingress for automatic TLS."
  type        = bool
  default     = true
}

variable "cluster_issuer_name" {
  description = "ClusterIssuer for cert-manager. Created out of band — the ACME account and solver depend on your DNS."
  type        = string
  default     = "letsencrypt-prod"
}

# --- chart versions ----------------------------------------------------------
#
# Pinned exactly. A floating version means an unrelated apply can upgrade the
# ingress controller, and the resulting outage has no obvious cause in the diff.

variable "external_secrets_version" {
  description = "External Secrets Operator chart version."
  type        = string
  default     = "0.10.7"
}

variable "ingress_nginx_version" {
  description = "ingress-nginx chart version."
  type        = string
  default     = "4.11.3"
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.16.2"
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "66.2.1"
}
