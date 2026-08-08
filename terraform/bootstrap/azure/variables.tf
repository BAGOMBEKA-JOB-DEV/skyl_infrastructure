variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "region" {
  description = "Region for the state storage account."
  type        = string
  default     = "westeurope"
}
