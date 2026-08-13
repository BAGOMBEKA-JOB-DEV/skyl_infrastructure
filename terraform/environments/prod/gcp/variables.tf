variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-west1"
}

variable "gateway_image_digest" {
  description = "Image digest to deploy. From skyl's publish-image workflow summary."
  type        = string
}

variable "gateway_hosts" {
  description = "Hostnames to serve. Required in prod — a production gateway nobody can reach is not a deployment."
  type        = list(string)

  validation {
    condition     = length(var.gateway_hosts) > 0
    error_message = "gateway_hosts must not be empty in prod; cert-manager also needs a host to issue for."
  }
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the Kubernetes API.

    Required, unlike dev. The API is authenticated either way, but a production
    control plane should not be reachable from the whole internet — and the
    module's default of "empty means open" is the wrong default to inherit
    silently here.
  EOT
  type = list(object({
    cidr = string
    name = string
  }))

  validation {
    condition     = length(var.authorized_networks) > 0
    error_message = "authorized_networks must not be empty in prod. Set it to your office and CI egress ranges."
  }
}
