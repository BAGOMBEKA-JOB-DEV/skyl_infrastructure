# dev on Azure.
#
# The `module "platform"` block is identical to the one in environments/dev/aws
# and environments/dev/gcp. That is the point.

terraform {
  required_version = ">= 1.9"

  backend "azurerm" {
    # resource_group_name, storage_account_name and container_name come from
    # -backend-config. Created by terraform/bootstrap/azure.
    key = "skyl/dev/azure/terraform.tfstate"
  }

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.10" }
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    kubectl    = { source = "alekc/kubectl", version = "~> 2.1" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

module "cluster" {
  source = "../../../modules/azure"

  name        = "skyl"
  environment = "dev"
  region      = var.region

  node_count = 2
  # Free has no uptime SLA. Correct for dev, wrong for prod.
  sku_tier = "Free"

  admin_group_object_ids = var.admin_group_object_ids
  authorized_networks    = var.authorized_networks
  key_vault_allowed_ips  = var.key_vault_allowed_ips
}

# local_account_disabled is true on the cluster, so kube_admin_config is empty.
# kube_config carries the Entra-backed credentials instead, and the token in it
# is what these providers use.
provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
    }
  }
}

provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args        = ["get-token", "--login", "azurecli", "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630"]
  }
}

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

  monitoring_enabled   = true
  grafana_enabled      = true
  cert_manager_enabled = length(var.gateway_hosts) > 0
}
