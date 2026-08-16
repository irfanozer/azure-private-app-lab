output "id" {
  description = "Web App resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "name" {
  description = "Web App name."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default Azure hostname. Use this hostname from inside the VNet so TLS and Private DNS both work."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "Object/principal ID of the system-assigned managed identity, used for RBAC."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

