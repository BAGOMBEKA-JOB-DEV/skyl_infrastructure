# GKE Autopilot for skyl-gateway.
#
# Autopilot rather than Standard: the gateway is a handful of stateless pods, so
# there is nothing to gain from managing node pools and a real cost to getting
# them wrong. Autopilot bills per pod resource request, enforces the security
# posture the chart already sets, and removes node upgrades from the operator's
# job entirely.
#
# The trade is that some knobs disappear — no DaemonSets on system nodes, no
# privileged pods, no custom node images. None of those are things this workload
# needs, and each one it cannot do is one it should not have been doing.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  cluster_name = "${var.name}-${var.environment}"

  labels = merge(var.tags, {
    managed-by  = "terraform"
    part-of     = "skyl"
    environment = var.environment
  })
}

# --- network -----------------------------------------------------------------
#
# A dedicated VPC, not `default`. The default network has permissive firewall
# rules and is shared with anything else in the project.

resource "google_compute_network" "this" {
  name                    = local.cluster_name
  auto_create_subnetworks = false
  description             = "skyl-gateway ${var.environment}"
}

resource "google_compute_subnetwork" "this" {
  name          = local.cluster_name
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges for VPC-native networking. Autopilot requires it, and it
  # is what allows pod IPs to be routable and NetworkPolicy to be enforced.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }

  # Flow logs are how an egress question gets answered after the fact. Sampled
  # at 50% because the gateway's traffic is low-volume and the cost is trivial.
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  private_ip_google_access = true
}

# Nodes have no public IPs, so egress to the provider APIs needs a NAT. Without
# this every model call fails with a connection timeout — and it presents as
# the gateway being broken rather than as a missing route.
resource "google_compute_router" "this" {
  name    = local.cluster_name
  network = google_compute_network.this.id
  region  = var.region
}

resource "google_compute_router_nat" "this" {
  name   = local.cluster_name
  router = google_compute_router.this.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- cluster -----------------------------------------------------------------

# trivy:ignore:GCP-0061 var.authorized_networks exists and is applied below; it defaults empty so dev is not gated on knowing your egress IP, exactly as the AWS and Azure modules default. Set it per environment.
# trivy:ignore:GCP-0050 Autopilot owns the node service account; a custom one cannot be set and is not the operator's to manage
resource "google_container_cluster" "this" {
  name     = local.cluster_name
  location = var.region

  enable_autopilot = true

  network    = google_compute_network.this.id
  subnetwork = google_compute_subnetwork.this.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private nodes, public endpoint. The endpoint is restricted by
  # master_authorized_networks below; making it fully private would require a
  # bastion or a VPN for every kubectl and for CI, which is a real operational
  # cost for a workload whose secrets live in Secret Manager rather than on the
  # nodes.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr
          display_name = cidr_blocks.value.name
        }
      }
    }
  }

  # Workload Identity. This is what lets the External Secrets ServiceAccount
  # read Secret Manager without a JSON key file existing anywhere.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.release_channel
  }

  # Autopilot enables NetworkPolicy unconditionally, so the chart's
  # NetworkPolicy is enforced rather than silently ignored — which is the
  # failure mode on a cluster without a policy-capable CNI.

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Deletion protection defaults to true in provider v6 and blocks `terraform
  # destroy` with an error that reads like a permissions problem. Off for dev,
  # on for anything else.
  deletion_protection = var.environment == "dev" ? false : true

  resource_labels = local.labels

  lifecycle {
    ignore_changes = [
      # Autopilot manages these and rewrites them; diffing on them produces a
      # permanent plan that never converges.
      node_config,
    ]
  }
}

# --- secret store identity ---------------------------------------------------
#
# External Secrets Operator reads Secret Manager. It authenticates as this
# Google service account, bound to its Kubernetes ServiceAccount by Workload
# Identity — so there is no key to rotate and none to leak.

resource "google_service_account" "external_secrets" {
  account_id   = substr("${local.cluster_name}-eso", 0, 30)
  display_name = "External Secrets for ${local.cluster_name}"
}

# secretAccessor, not admin: ESO reads. It never writes, and never lists other
# projects' secrets.
resource "google_project_iam_member" "external_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.external_secrets.email}"
}

resource "google_service_account_iam_member" "external_secrets_wi" {
  service_account_id = google_service_account.external_secrets.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.external_secrets_namespace}/${var.external_secrets_sa_name}]"
}

# --- secrets -----------------------------------------------------------------
#
# The containers are created here; the values are not. Putting a secret value in
# Terraform writes it to state in plaintext, and state is the one file that gets
# copied around. Populate with:
#
#   echo -n "$TOKEN" | gcloud secrets versions add skyl-gateway-auth-token --data-file=-

resource "google_secret_manager_secret" "gateway" {
  for_each = toset(var.secret_names)

  secret_id = each.value
  labels    = local.labels

  replication {
    auto {}
  }
}
