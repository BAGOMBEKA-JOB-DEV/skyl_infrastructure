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

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
