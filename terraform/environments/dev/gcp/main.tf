# dev on GCP.
#
# The composition is the same three blocks in every environment: a cloud module,
# a platform module wired to its contract outputs, and provider configuration
# derived from the cluster. Swapping cloud means changing the `source` on the
# first block and its inputs — the platform block below is byte-identical
# across aws/, gcp/ and azure/. That is the contract paying for itself.

terraform {
  required_version = ">= 1.9"

  # State backend. Created by terraform/bootstrap/gcp before the first apply
  # here — the bucket cannot be in the state it stores.
  backend "gcs" {
    # bucket is supplied by -backend-config, since it embeds the project ID.
    prefix = "skyl/dev/gcp"
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
  environment = "dev"
  region      = var.region

  # Dev is reachable from anywhere by default. Narrow this even in dev if you
  # can — the API is authenticated, but there is no reason to advertise it.
  authorized_networks = var.authorized_networks

  tags = {
    owner = "platform"
  }
}

# Kubernetes providers cannot be configured until the cluster exists, and
# Terraform will not let a provider depend on a resource. An access token from
# the google provider avoids a two-stage apply: it is resolved at plan time from
# the caller's own credentials, not from the cluster.
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

# Identical in every environment. Only the inputs above it change.
module "platform" {
  source = "../../../modules/platform"

  environment = "dev"

  cluster_name                 = module.cluster.cluster_name
  region                       = module.cluster.region
  workload_identity_annotation = module.cluster.workload_identity_annotation
  secret_store_backend         = module.cluster.secret_store_backend
  secret_store_config          = module.cluster.secret_store_config
  ingress_class                = module.cluster.ingress_class
  node_architecture            = module.cluster.node_architecture

  gateway_image_digest = var.gateway_image_digest
  gateway_hosts        = var.gateway_hosts

  # Dev runs the full observability stack — it is where you learn what the
  # alerts do before they page you from prod.
  monitoring_enabled   = true
  grafana_enabled      = true
  cert_manager_enabled = length(var.gateway_hosts) > 0
}
