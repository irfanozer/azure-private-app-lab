output "id" {
  description = "Private DNS Resolver resource ID."
  value       = azurerm_private_dns_resolver.this.id
}

output "inbound_ip_address" {
  description = "IP address to which external/private DNS servers forward Azure-private queries."
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_address
}

output "outbound_endpoint_id" {
  description = "Outbound endpoint used by the forwarding ruleset."
  value       = azurerm_private_dns_resolver_outbound_endpoint.this.id
}

