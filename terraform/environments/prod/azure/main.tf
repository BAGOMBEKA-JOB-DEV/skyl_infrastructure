# prod on Azure.
#
# The `module "platform"` block is byte-identical to the other five
# environments. Only the cluster inputs and the provider wiring differ.

terraform {
  required_version = ">= 1.9"

  backend "azurerm" {
    key = "skyl/prod/azure/terraform.tfstate"
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
  environment = "prod"
  region      = var.region

  node_count = 3

  # Standard, not Free. The Free tier has no uptime SLA on the control plane,
  # which is a reasonable trade in dev and not one to make here. ~$73/month.
  sku_tier = "Standard"

  admin_group_object_ids = var.admin_group_object_ids
  authorized_networks    = var.authorized_networks
  key_vault_allowed_ips  = var.key_vault_allowed_ips
}

# environment = "prod" also turns on Key Vault purge protection in the module,
# which CANNOT be disabled once set and reserves the vault name for the
# retention period. That is the correct posture for production and an expensive
# accident anywhere else — it is why the module keys it off the environment
# rather than defaulting it on.

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
