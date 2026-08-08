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
  description = <<-EOT
    Image digest to deploy. Printed by skyl's publish-image workflow, or:

      crane digest ghcr.io/bagombeka-job-dev/skyl-gateway:0.1.0
  EOT
  type        = string
}

variable "gateway_hosts" {
  description = "Hostnames to serve. Empty leaves the gateway in-cluster only, reachable via port-forward."
  type        = list(string)
  default     = []
}

variable "authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API."
  type = list(object({
    cidr = string
    name = string
  }))
  default = []
}
