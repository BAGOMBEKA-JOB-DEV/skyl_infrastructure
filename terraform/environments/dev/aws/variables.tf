variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
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
  default     = ["0.0.0.0/0"]
}
