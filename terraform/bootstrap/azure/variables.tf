variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "region" {
  description = "Region for the state storage account."
  type        = string
  default     = "westeurope"
}

variable "allowed_ips" {
  description = <<-EOT
    Public IPs allowed to reach the state storage account, on top of the
    `AzureServices` bypass.

    The account denies by default. If this is empty and you are not coming from
    an Azure service, `terraform init` against this backend fails with a 403 —
    put your own address and your CI runner's egress range here.
  EOT
  type        = list(string)
  default     = []
}
