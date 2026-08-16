output "ids" {
  description = "Map of Private Endpoint resource IDs."
  value       = { for key, endpoint in azurerm_private_endpoint.this : key => endpoint.id }
}

output "private_ip_addresses" {
  description = "Map of endpoint key to allocated private IP address."
  value = {
    for key, endpoint in azurerm_private_endpoint.this :
    key => try(endpoint.private_service_connection[0].private_ip_address, null)
  }
}

