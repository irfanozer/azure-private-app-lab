output "virtual_network_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "app_integration_subnet_id" {
  description = "Delegated subnet used for App Service outbound VNet integration."
  value       = azurerm_subnet.app_integration.id
}

output "private_endpoint_subnet_id" {
  description = "Subnet used by Private Endpoint NICs."
  value       = azurerm_subnet.private_endpoints.id
}

output "dns_resolver_inbound_subnet_id" {
  description = "Dedicated inbound resolver subnet, or null when disabled."
  value       = try(azurerm_subnet.dns_resolver_inbound[0].id, null)
}

output "dns_resolver_outbound_subnet_id" {
  description = "Dedicated outbound resolver subnet, or null when disabled."
  value       = try(azurerm_subnet.dns_resolver_outbound[0].id, null)
}

