# Remote state backend for Azure environments.
#
# Applied once, with local state. See ../README.md.

terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "state" {
  name     = "skyl-tfstate"
  location = var.region

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate"
  }
}

# Storage account names are globally unique, max 24 chars, lowercase
# alphanumeric only — no hyphens. A random suffix avoids collisions with
# anyone else's "skyltfstate".
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# trivy:ignore:AZU-0060 customer-managed keys deliberately not used — a CMK on the state account adds a deletion path that locks you out of your own state
# trivy:ignore:AZU-0057 this check reads queue_properties.logging; the account serves blobs only, and blob access is audited by the diagnostic setting below, which is the log that would actually be read
resource "azurerm_storage_account" "state" {
  name                = "skyltfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_replication_type = "GRS"

  # State is not public, ever.
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"

  # Double encryption, at the infrastructure layer as well as the service
  # layer. Free, and this account holds every environment's state.
  infrastructure_encryption_enabled = true

  # Deny by default. Terraform state contains resource attributes that are
  # secrets in practice, so the blob endpoint should not answer the internet.
  #
  # Two escape hatches, both deliberate:
  #
  #   bypass = AzureServices  lets Azure's own control plane in. Without it,
  #                           portal access and diagnostic settings break.
  #   ip_rules                is where your own address goes. **Without at
  #                           least one entry, or a service endpoint, you
  #                           cannot read your own state** — including from
  #                           CI. Leaving it empty is the safe default only
  #                           because the very next `terraform init` will tell
  #                           you loudly.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ips
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate"
  }
}

# Who read and wrote state, and when. The one audit trail worth having on a
# bucket whose contents describe every cluster you run.
resource "azurerm_log_analytics_workspace" "state" {
  name                = "skyl-tfstate-logs"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    ManagedBy = "terraform"
    PartOf    = "skyl"
    Purpose   = "tfstate"
  }
}

resource "azurerm_monitor_diagnostic_setting" "state_blob" {
  name = "tfstate-blob-audit"
  # The blob service, not the account: StorageRead/Write/Delete are emitted by
  # the service resource, and pointing this at the account id yields a setting
  # with no available log categories.
  target_resource_id         = "${azurerm_storage_account.state.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.state.id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
