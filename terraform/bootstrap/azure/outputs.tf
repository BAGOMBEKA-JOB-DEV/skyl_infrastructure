output "resource_group" {
  description = "Resource group. Pass as -backend-config=\"resource_group_name=...\"."
  value       = azurerm_resource_group.state.name
}

output "storage_account" {
  description = "Storage account. Pass as -backend-config=\"storage_account_name=...\"."
  value       = azurerm_storage_account.state.name
}

output "container" {
  description = "Blob container. Pass as -backend-config=\"container_name=...\"."
  value       = azurerm_storage_container.state.name
}
