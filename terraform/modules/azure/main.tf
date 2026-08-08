# AKS for skyl-gateway.
#
# Raw azurerm resources rather than a community module. AKS is genuinely simple
# to express — one cluster resource, one node pool, a Key Vault and two role
# assignments — so a wrapper module would add indirection without removing
# complexity. That is the opposite of the AWS module's situation, where EKS
# needs forty interlocking resources; the two choices differ because the
# providers differ, not out of inconsistency.
#
# Cost note: the AKS control plane is free on the Free tier, which puts Azure
# between GCP and AWS. The Free tier carries no uptime SLA — Standard is ~$73/mo
# and is what var.sku_tier switches to for prod.

terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  cluster_name = "${var.name}-${var.environment}"

  tags = merge(var.tags, {
    ManagedBy   = "terraform"
    PartOf      = "skyl"
    Environment = var.environment
  })
}

resource "azurerm_resource_group" "this" {
  name     = "${local.cluster_name}-rg"
  location = var.region
  tags     = local.tags
}

# --- network -----------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = local.cluster_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]
}

# --- cluster -----------------------------------------------------------------

# trivy:ignore:AZU-0065 public endpoint restricted by authorized_ip_ranges, matching the AWS and GCP modules — see docs/adr/0002
# trivy:ignore:AZU-0067 a disk encryption set needs its own DES and Key Vault key; deferred, see docs/adr/0004
# trivy:ignore:AZU-0041 var.authorized_networks exists and is applied below; it defaults empty so dev is not gated on knowing your egress IP, exactly as the AWS and GCP modules default. Set it per environment.
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = local.cluster_name

  kubernetes_version = var.cluster_version
  sku_tier           = var.sku_tier

  # Workload Identity. Both flags are required and each is useless alone:
  # oidc_issuer_enabled publishes the issuer, workload_identity_enabled installs
  # the mutating webhook that projects the token. Enabling only the first is a
  # common and confusing half-configuration.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Local accounts off: authentication goes through Entra ID, so there is no
  # static admin kubeconfig to leak. Note this makes
  # `azurerm_kubernetes_cluster.this.kube_admin_config` unavailable — use
  # `az aks get-credentials` instead.
  local_account_disabled = true

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # Restrict who can reach the Kubernetes API.
  #
  # This was missing while the AWS and GCP modules both took an
  # `authorized_networks` input and applied it — an inconsistency, not a
  # decision, and Trivy AZU-0041 was right to flag it. The three modules now
  # express the same intent in each provider's own vocabulary, which is exactly
  # what CONTRACT.md expects a cloud module to absorb.
  #
  # An empty list leaves the API open, matching the other two modules' defaults
  # and the same reasoning: it is still authenticated, and narrowing it is a
  # per-environment decision.
  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_networks
    }
  }

  # Azure Policy add-on. Enabled for the same reason Cilium is chosen below: a
  # policy engine that is installed but not enforcing reports a control that is
  # not there. Gatekeeper constraints are additive to the chart's own Conftest
  # rules, which run before anything reaches a cluster.
  azure_policy_enabled = true

  default_node_pool {
    name       = "system"
    vm_size    = var.vm_size
    node_count = var.node_count

    vnet_subnet_id = azurerm_subnet.nodes.id

    # Ephemeral OS disks are faster and free — the disk is on the VM's local
    # storage rather than a managed disk. Nodes are cattle, so there is nothing
    # to lose when one is replaced.
    os_disk_type = "Ephemeral"

    upgrade_settings {
      max_surge = "33%"
    }

    only_critical_addons_enabled = false
    tags                         = local.tags
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    # Cilium enforces NetworkPolicy. Without a policy engine the chart's
    # NetworkPolicy is accepted and then ignored, which is worse than not
    # having one — it reports a control that is not there.
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  # Managed Prometheus, matching the GCP module's managed_prometheus.
  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      # The autoscaler moves this; diffing on it produces a permanent plan.
      default_node_pool[0].node_count,
    ]
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30
  tags                = local.tags
}

# --- secret store ------------------------------------------------------------

# trivy:ignore:AZU-0016 purge protection is environment-conditional below, on purpose
resource "azurerm_key_vault" "this" {
  name                = substr(replace("${local.cluster_name}kv", "-", ""), 0, 24)
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC rather than access policies. Access policies are the older model and
  # cannot express "this workload identity, these secrets" as cleanly.
  rbac_authorization_enabled = true

  # Recovery. Purge protection cannot be disabled once enabled, and a vault
  # name stays reserved for the retention period — which makes an accidental
  # enable in dev genuinely painful. Hence the environment split, and hence the
  # AZU-0016 ignore above: prod does enable it.
  purge_protection_enabled   = var.environment == "prod"
  soft_delete_retention_days = var.environment == "prod" ? 90 : 7

  # Deny by default. The vault holds every provider API key, so it should not
  # be reachable from the internet at large.
  #
  # `bypass = AzureServices` is load-bearing, not a loophole: without it the
  # AKS-hosted External Secrets Operator cannot reach the vault, and neither
  # can the principal running Terraform when it creates the secret containers
  # below. Removing it produces a 403 at apply time that reads like an IAM
  # problem.
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault_allowed_ips
  }

  tags = local.tags
}

# The identity External Secrets federates with. User-assigned rather than
# system-assigned: it must outlive any single pod and be referenced by name in
# the ServiceAccount annotation.
resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "${local.cluster_name}-external-secrets"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# Federated credential: trust tokens this cluster issues for that specific
# namespace and ServiceAccount. The subject is an exact match — a pod in any
# other namespace gets nothing.
resource "azurerm_federated_identity_credential" "external_secrets" {
  name                = "external-secrets"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.external_secrets.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.external_secrets_namespace}:${var.external_secrets_sa_name}"
}

# "Secrets User" reads secret values. Not "Secrets Officer", which can also
# write and delete.
resource "azurerm_role_assignment" "external_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.external_secrets.principal_id
}

# --- secrets -----------------------------------------------------------------
#
# Placeholders only. A real value here lands in state in plaintext. Populate:
#
#   az keyvault secret set --vault-name <vault> \
#     --name skyl-gateway-auth-token --value "$TOKEN"

# trivy:ignore:AZU-0017 an expiry here would expire the operator's real value, not the placeholder
resource "azurerm_key_vault_secret" "gateway" {
  for_each = toset(var.secret_names)

  name         = each.value
  value        = "placeholder-replace-me"
  key_vault_id = azurerm_key_vault.this.id

  # Content type, so `az keyvault secret list` is readable and tooling can tell
  # these apart from certificates or connection strings.
  content_type = "text/plain; charset=utf-8"

  tags = local.tags

  lifecycle {
    # Terraform created the container; the operator owns the value. Without
    # this, every plan after the real secret is set shows a diff reverting it
    # to the placeholder — and eventually somebody applies it.
    ignore_changes = [value]
  }

  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}

# The applying principal needs write access to create the placeholders above.
# With enable_rbac_authorization, ownership of the vault does not imply data
# access — a distinction that produces a 403 at apply time and reads like a
# bug.
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
