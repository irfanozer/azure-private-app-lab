output "id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "Public-form Blob hostname; inside the linked VNet DNS resolves it to the Private Endpoint IP."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

