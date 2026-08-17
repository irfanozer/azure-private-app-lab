output "virtual_network_id" {
  description = "VNet resource ID."
  value       = azurerm_virtual_network.this.id
}

output "compute_subnet_id" {
  description = "Subnet containing the Linux VM NIC."
  value       = azurerm_subnet.compute.id
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
