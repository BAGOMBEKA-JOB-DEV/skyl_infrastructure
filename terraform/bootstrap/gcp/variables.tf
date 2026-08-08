variable "project_id" {
  description = "GCP project ID. Also forms the globally-unique bucket name."
  type        = string
}

variable "region" {
  description = "Bucket location."
  type        = string
  default     = "europe-west1"
}
