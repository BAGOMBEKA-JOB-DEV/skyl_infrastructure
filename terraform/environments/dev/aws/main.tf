# dev on AWS.
#
# Compare the `module "platform"` block with environments/dev/gcp and
# environments/dev/azure: they are identical. Only the cloud module and its
# provider wiring differ. If a change here needs a matching change there, the
# contract has leaked.

terraform {
  required_version = ">= 1.9"

  backend "s3" {
    # bucket and dynamodb_table come from -backend-config; they embed the
    # account ID. Created by terraform/bootstrap/aws.
    key    = "skyl/dev/aws/terraform.tfstate"
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
  environment = "dev"
  region      = var.region

  node_count          = 2
  single_nat_gateway  = true
  authorized_networks = var.authorized_networks
}

# A short-lived token rather than exec-based auth. `exec` requires the aws CLI
# on the machine running Terraform, which is one more thing to install in CI;
# the data source needs only the provider credentials already configured.
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
