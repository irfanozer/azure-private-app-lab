output "zone_ids" {
  description = "Map of logical zone key to Private DNS zone resource ID."
  value       = { for key, zone in azurerm_private_dns_zone.this : key => zone.id }
}

output "zone_names" {
  description = "Map of logical zone key to Private DNS zone name."
  value       = { for key, zone in azurerm_private_dns_zone.this : key => zone.name }
}

