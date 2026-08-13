# prod on GCP.
#
# Identical in shape to environments/dev/gcp — the `module "platform"` block is
# byte-identical, which is the contract doing its job. What differs is only the
# inputs, and each difference below is a decision rather than a default.
#
# Until this existed, every `var.environment == "prod"` branch in the modules
# was unreachable: nothing set it. They were untested code paths wearing
# configuration's clothes.

terraform {
  required_version = ">= 1.9"

  backend "gcs" {
    prefix = "skyl/prod/gcp"
  }

  required_providers {
    google     = { source = "hashicorp/google", version = "~> 6.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    kubectl    = { source = "alekc/kubectl", version = "~> 2.1" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "cluster" {
  source = "../../../modules/gcp"

  project_id  = var.project_id
  name        = "skyl"
  environment = "prod"
  region      = var.region

  # Required here, unlike dev. An open API server is defensible while you are
  # learning the shape of a thing; it is not defensible in production. The
  # variable below refuses an empty list.
  authorized_networks = var.authorized_networks

  # STABLE, not REGULAR. Production takes upgrades late and deliberately.
  release_channel = "STABLE"

  tags = {
    owner = "platform"
  }
}

data "google_client_config" "current" {}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}

provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
  load_config_file       = false
}

module "platform" {
  source = "../../../modules/platform"

  environment = "prod"

  cluster_name                 = module.cluster.cluster_name
  region                       = module.cluster.region
  workload_identity_annotation = module.cluster.workload_identity_annotation
  secret_store_backend         = module.cluster.secret_store_backend
  secret_store_config          = module.cluster.secret_store_config
  ingress_class                = module.cluster.ingress_class
  node_architecture            = module.cluster.node_architecture

  gateway_image_digest = var.gateway_image_digest
  gateway_hosts        = var.gateway_hosts

  monitoring_enabled   = true
  grafana_enabled      = true
  cert_manager_enabled = true
}
