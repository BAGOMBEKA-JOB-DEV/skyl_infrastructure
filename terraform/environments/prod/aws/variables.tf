variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
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
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API.

    Required, and explicitly not defaulted. The AWS module's own default is
    0.0.0.0/0 — correct as a module default, wrong to inherit silently in
    production.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.authorized_networks) > 0 && !contains(var.authorized_networks, "0.0.0.0/0")
    error_message = "authorized_networks must be set in prod and must not be 0.0.0.0/0."
  }
}
