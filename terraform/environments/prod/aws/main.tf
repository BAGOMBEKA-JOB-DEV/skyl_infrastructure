# prod on AWS.
#
# The `module "platform"` block is byte-identical to the other five
# environments. Only the cluster inputs and the provider wiring differ.

terraform {
  required_version = ">= 1.9"

  backend "s3" {
    key    = "skyl/prod/aws/terraform.tfstate"
    region = "eu-west-1"
  }

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.70" }
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    kubectl    = { source = "alekc/kubectl", version = "~> 2.1" }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      PartOf    = "skyl"
      Repo      = "skyl_infrastructure"
    }
  }
}

module "cluster" {
  source = "../../../modules/aws"

  name        = "skyl"
  environment = "prod"
  region      = var.region

  # Three nodes, one per AZ, so the topology spread constraint and the PDB can
  # both be satisfied while a node is draining for an upgrade.
  node_count = 3

  # One NAT per AZ. Costs ~$66/month more than the dev default and removes a
  # single point of failure for every outbound model call — see docs/cost.md.
  single_nat_gateway = false

  authorized_networks = var.authorized_networks
}

data "aws_eks_cluster_auth" "this" {
  name = module.cluster.cluster_name
}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
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
