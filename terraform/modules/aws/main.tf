# EKS for skyl-gateway.
#
# Built on the community VPC and EKS modules rather than raw resources. That is
# not laziness: EKS needs around forty interlocking resources — OIDC provider,
# node IAM roles, four managed add-ons, security group rules, aws-auth — and a
# hand-rolled version of that is a liability nobody reviews properly. The
# modules are the de facto standard and are pinned to an exact minor below.
#
# Cost, stated plainly because it surprises people: the EKS control plane is
# ~$73/month whether or not anything runs on it. GKE Autopilot's first cluster
# has no control-plane fee. If this is a demo rather than production, GCP is the
# cheaper module to point at — see docs/cost.md.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "${var.name}-${var.environment}"

  # Three AZs. Two is enough for the topologySpreadConstraint but leaves no
  # margin during a zonal event plus a rolling node upgrade.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    PartOf      = "skyl"
    Environment = var.environment
  })
}

# --- network -----------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"

  name = local.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  # Nodes are private and reach provider APIs through NAT. One gateway rather
  # than one per AZ: it is a ~$32/month saving and the failure mode is degraded
  # egress during a zonal outage, not data loss. Set single_nat_gateway=false
  # for prod if that trade is wrong for you.
  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required by the AWS load balancer controller to discover where to place
  # load balancers. Without them, Service type=LoadBalancer silently never
  # provisions and the event log says only "no matching subnets".
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  enable_flow_log                      = var.environment == "prod"
  create_flow_log_cloudwatch_log_group = var.environment == "prod"
  create_flow_log_cloudwatch_iam_role  = var.environment == "prod"

  tags = local.tags
}

# --- cluster -----------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.6"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint, restricted by CIDR. Fully private needs a bastion or VPN
  # for kubectl and for CI; the same trade as the GCP module, made the same way.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.authorized_networks
  cluster_endpoint_private_access      = true

  # IRSA. This is what lets External Secrets assume a role without a stored
  # access key.
  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    # VPC CNI is what enforces NetworkPolicy on EKS. Without ENABLE_NETWORK_POLICY
    # the chart's NetworkPolicy object is accepted by the API server and then
    # ignored — the worst kind of security control, one that reports success.
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
    eks-pod-identity-agent = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      # Graviton. The gateway image is built for arm64 as well as amd64
      # precisely so this is available: roughly 20% cheaper for identical
      # throughput on an I/O-bound service.
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = var.instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_count
      max_size     = var.node_count * 3
      desired_size = var.node_count

      # IMDSv2 with hop limit 1. A pod cannot then reach the instance metadata
      # service to steal the node role — the same attack the chart's
      # NetworkPolicy blocks at 169.254.169.254, defended twice because the
      # gateway holds provider API keys.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      labels = {
        "kubernetes.io/arch" = "arm64"
      }
    }
  }

  # Cluster creator gets admin. Without this the applying principal has no
  # Kubernetes RBAC at all and every kubectl returns Forbidden — a confusing
  # first five minutes on a fresh cluster.
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  tags = local.tags
}

# --- secret store identity ---------------------------------------------------

data "aws_iam_policy_document" "external_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped by name prefix, not "*". A compromised ESO should not be able to
    # read every secret in the account.
    resources = [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:skyl-*",
    ]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "external_secrets" {
  name        = "${local.cluster_name}-external-secrets"
  description = "Read skyl-* secrets for External Secrets Operator"
  policy      = data.aws_iam_policy_document.external_secrets.json
  tags        = local.tags
}

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"

  role_name = "${local.cluster_name}-external-secrets"

  role_policy_arns = {
    read = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.external_secrets_namespace}:${var.external_secrets_sa_name}"]
    }
  }

  tags = local.tags
}

# --- secrets -----------------------------------------------------------------
#
# Containers only. A value here is a value in state, in plaintext. Populate:
#
#   aws secretsmanager put-secret-value \
#     --secret-id skyl-gateway-auth-token --secret-string "$TOKEN"

# trivy:ignore:AWS-0098 the AWS-managed key is sufficient here; a CMK adds a deletion path that would make the provider keys unrecoverable, and access is already scoped to skyl-* by the IRSA policy above
resource "aws_secretsmanager_secret" "gateway" {
  for_each = toset(var.secret_names)

  name = each.value
  # Zero in dev so a destroy-and-recreate cycle is not blocked for a week by
  # the name still being reserved. Production keeps the recovery window.
  recovery_window_in_days = var.environment == "dev" ? 0 : 30

  tags = local.tags
}
